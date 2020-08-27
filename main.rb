# frozen_string_literal: true

require 'octokit'
require 'sqlite3'
require 'time'
require 'yaml'

def main
  issues_comments = fetch_issues_comments
  communication_comments = extract_communication_comments(issues_comments)
  unless communication_comments.empty?
    insert_comments(communication_comments)
    update_comments_to_replied
    update_comments_to_done
    update_comments_to_stop_my_reminder
  end

  unreplied_comment_rows = fetch_unreplied_comments
  notify(unreplied_comment_rows)
end

def fetch_issues_comments(sort: 'created', direction: 'asc', since: nil)
  since ||= make_since_time
  issues_comments = client.issues_comments(
    github_config['repo_name'],
    sort: sort,
    direction: direction,
    since: since,
  )
  insert_last_fetch_at
  issues_comments
end

def extract_communication_comments(issues_comments)
  pickup_keys = users.map { |x| "@#{x.login}" } + [reminder_stop_key, reminder_all_stop_key]
  mentioned_comments = issues_comments.select do |comment|
    pickup_keys.any? { |key| comment.body.include?(key) }
  end
  mentioned_comments.reject do |comment|
    comment.body.include?(reminder_bot_message)
  end
end

def insert_comments(communication_comments)
  insert = <<-"SQL"
    INSERT OR IGNORE INTO issues_comments (#{columns.keys.join(',')})
    VALUES
  SQL
  mention_to_and_comments = group_by_mention_to(communication_comments)
  values = make_values(mention_to_and_comments)
  sql = "#{insert} #{values};"
  db.execute(sql)
end

def group_by_mention_to(communication_comments)
  communication_comments.flat_map do |comment|
    mention_to_and_comments = comment.body.scan(/@\S+/).map do |mention_to|
      [mention_to, comment]
    end

    if comment.body.include?(reminder_stop_key)
      mention_to_and_comments += [[reminder_stop_key, comment]]
    end

    if comment.body.include?(reminder_all_stop_key)
      mention_to_and_comments = [[reminder_all_stop_key, comment]]
    end

    mention_to_and_comments
  end
end

def make_values(mention_to_and_comments) # rubocop:disable Metrics/MethodLength
  mention_to_and_comments.map do |mention_to, comment|
    mention_from = "@#{comment.user.login}"
    replied = mention_to == reminder_all_stop_key ? 1 : 0
    <<-"SQL"
      (
        '#{comment.issue_url}',
        '#{comment.created_at}',
        '#{mention_from}',
        '#{mention_to}',
        #{replied}
      )
    SQL
  end.join(',')
end

def update_comments_to_replied # rubocop:disable Metrics/MethodLength
  update = <<-"SQL"
    UPDATE issues_comments
    SET replied = 1
    WHERE id IN (
      SELECT c1.id
      FROM issues_comments c1
      JOIN issues_comments c2 on c1.issue_url = c2.issue_url
      WHERE c1.created_at < c2.created_at
        AND c1.replied = 0
        AND c1.mention_from = c2.mention_to
    );
  SQL
  db.execute(update)
end

def update_comments_to_done # rubocop:disable Metrics/MethodLength
  update = <<-"SQL"
    UPDATE issues_comments
    SET replied = 1
    WHERE id IN (
      SELECT c1.id
      FROM issues_comments c1
      JOIN issues_comments c2 on c1.issue_url = c2.issue_url
      WHERE c1.created_at < c2.created_at
        AND c1.replied = 0
        AND c2.mention_to = '#{reminder_all_stop_key}'
    );
  SQL
  db.execute(update)
end

def update_comments_to_stop_my_reminder
  update = <<-"SQL"
    UPDATE issues_comments
    SET replied = 1
    WHERE id IN (
      SELECT c1.id
      FROM issues_comments c1
      JOIN issues_comments c2 on c1.issue_url = c2.issue_url
      WHERE c1.created_at < c2.created_at
        AND c1.replied = 0
        AND c2.mention_to = '#{reminder_stop_key}'
        AND c2.mention_from = c1.mention_to
    );
  SQL
  db.execute(update)
end

def fetch_unreplied_comments
  sql = <<-"SQL"
    SELECT issue_url, mention_to
    FROM issues_comments
    WHERE replied = 0
    GROUP BY issue_url, mention_to
  ;
  SQL
  db.execute(sql)
end

def notify(unreplied_comment_rows)
  unreplied_comment_rows.each do |issue_url, mention_to|
    number = File.basename(issue_url)
    comment = make_reminder_message(mention_to)
    client.add_comment(github_config['repo_name'], number, comment)
    sleep 1
  end
end

def make_reminder_message(mention_to)
  format(
    config['reminder_message_template'],
    mention_to: mention_to,
    reminder_stop_key: reminder_stop_key.sub('[', '&#91;').sub(']', '&#93;'),
    reminder_all_stop_key: reminder_all_stop_key.sub('[', '&#91;').sub(']', '&#93;'),
  )
end

def db
  db = SQLite3::Database.new('./issues_comments.sqlite3')
  create_table_issues_comments(db)
  create_table_fetchs(db)
  db
end

def create_table_issues_comments(db)
  create_sql = <<-"SQL"
    CREATE TABLE IF NOT EXISTS issues_comments (
      id integer primary key autoincrement,
      #{columns.map { |k, v| "#{k} #{v}" }.join(',')},
      unique(issue_url, created_at, mention_from, mention_to)
    );
  SQL
  db.execute(create_sql)
end

def columns
  {
    issue_url: 'TEXT',
    created_at: 'TEXT',
    mention_from: 'TEXT',
    mention_to: 'TEXT',
    replied: 'INTEGER',
  }.freeze
end

def create_table_fetchs(db)
  create_sql = <<-"SQL"
    CREATE TABLE IF NOT EXISTS fetchs (
      id integer primary key autoincrement,
      fetch_at text
    );
  SQL
  db.execute(create_sql)
end

def users
  if github_config['org'] && github_config['team_slug']
    fetch_team_members(github_config['org'], github_config['team_slug'])
  else
    github_config['users'].map { |name| client.user(name) }
  end
end

def fetch_team_members(org, team_slug)
  organization_teams = client.organization_teams(org)
  team = organization_teams.find { |x| x[:slug] == team_slug }
  client.team_members(team[:id])
end

def make_since_time
  last_fetch_at = fetch_last_fetch_at
  return last_fetch_at if last_fetch_at

  one_minute_ago
end

def fetch_last_fetch_at
  sql = 'SELECT fetch_at FROM fetchs ORDER BY id DESC;'
  db.get_first_value(sql)
end

def insert_last_fetch_at
  update = 'INSERT INTO fetchs(fetch_at) VALUES(?);'
  db.query(update, [one_minute_ago])
end

def one_minute_ago
  (Time.now - 60).utc.iso8601
end

def client
  access_token = ENV['GITHUB_ACCESS_TOKEN'] || github_config['access_token']
  @client ||= Octokit::Client.new(
    access_token: access_token,
    auto_paginate: true,
  )
end

def github_config
  config['github']
end

def reminder_stop_key
  config['reminder_stop_key']
end

def reminder_all_stop_key
  config['reminder_all_stop_key']
end

def config
  @config ||= YAML.load_file('./config.yml')
end

def reminder_bot_message
  @reminder_bot_message ||= make_reminder_message('')
end

main if $PROGRAM_NAME == __FILE__
