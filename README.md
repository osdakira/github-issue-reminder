# github-issue-reminder

This is a reminder tool for issues on github.
This is meant to be used with cron.

## Installation

Clone the git repository and do a bundle install.

```
git clone git@github.com:osdakira/github-issue-reminder.git
cd github-issue-reminder
bundle install –deployment
```

Write the github configuration in yaml.

- repo_name: required
- users or org,team_slug: either
  - users: When this user has a mention, you will be reminded.s
  - org,team_slug: The team is set up, members will be selected.
- number_of_minutes_dating_back: Decide how many minutes ago you want to get from a comment that was made
- reminder_stop_key: When you no longer need to be reminded, please comment on this keyword!
- reminder_message_template: You can customize reminder message template.

```
github:
  repo_name: osdakira/github-issue-reminder
  # users or [org,team_slug]
  users:
    - osdakira
number_of_minutes_dating_back: 120
reminder_stop_key: '[ok]'
reminder_message_template: '%{mention_to} from github-auto-reminder'
```

Get the github api token.

https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line

Set the environment variable named GITHUB_ACCESS_TOKEN.
Or set cron directly

```
0 */2 * * * cd ./github-issue-reminder; GITHUB_ACCESS_TOKEN=*** bundle exec main.rb
```

or

```
export GITHUB_ACCESS_TOKEN=****
0 */2 * * * cd ./github-issue-reminder; bundle exec main.rb
```
