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

Get the github api token.

https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line

Write the github configuration in yaml.

- access_token: set or use environment variable
- repo_name: required
- users or org,team_slug: either
  - users: When this user has a mention, you will be reminded.s
  - org,team_slug: The team is set up, members will be selected.
- reminder_stop_key: When you no longer need to be reminded, please comment on this keyword!
- reminder_message_template: You can customize reminder message template.

```
github:
  access_token: ****
  repo_name: osdakira/github-issue-reminder
  # users or [org,team_slug]
  users:
    - osdakira
reminder_stop_key: '[ok]'
reminder_message_template: '%{mention_to} from github-auto-reminder'
```

Set cron.

```
0 */2 * * * cd ./github-issue-reminder; bundle exec main.rb
```


When you don't set access_token in yaml, use the environment variable named GITHUB_ACCESS_TOKEN.
Or set cron directly

```
0 */2 * * * cd ./github-issue-reminder; GITHUB_ACCESS_TOKEN=*** bundle exec main.rb
```

or

```
export GITHUB_ACCESS_TOKEN=****
0 */2 * * * cd ./github-issue-reminder; bundle exec main.rb
```
