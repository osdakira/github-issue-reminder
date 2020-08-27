# frozen_string_literal: true

require 'test/unit'
require 'ostruct'

require './main'

class MainTest < Test::Unit::TestCase
  def setup
    system('rm issues_comments_test.sqlite3')
    config['db_name'] = 'issues_comments_test.sqlite3'
  end

  def users
    %w[user_a user_b user_c].map { |name| OpenStruct.new(login: name) }
  end

  def client
    Struct.new('GithubClient') do
      def make_comment(body, issue_url, created_at, login)
        OpenStruct.new(body: body, issue_url: issue_url, created_at: created_at, user: OpenStruct.new(login: login))
      end

      def issues_comments(*args)
        [
          make_comment('to @user_b @user_c', 'url_1', '2020-08-27 00:00:00', 'user_a'),
          make_comment('[ok]', 'url_1', '2020-08-27 00:00:10', 'user_b'),

          make_comment('to @user_b @user_c', 'url_2', '2020-08-27 00:00:00', 'user_a'),
          make_comment('[no-reminder]', 'url_2', '2020-08-27 00:00:10', 'user_b'),
        ]
      end
    end.new
  end

  def test_main
    main

    rows = db.execute("select * from issues_comments")

    # when user_b writes [ok], stop reminder only for user_b, not stop for user_c
    assert_equal(["@user_a", "@user_b", 1], rows[0][-3..-1])
    assert_equal(["@user_a", "@user_c", 0], rows[1][-3..-1])

    # when user_b writes [no-reminder], stop reminder for all
    assert_equal(["@user_a", "@user_b", 1], rows[3][-3..-1])
    assert_equal(["@user_a", "@user_c", 1], rows[4][-3..-1])
  end
end
