require_relative 'redmine_issue_repeat/issue_patch'
require_relative 'redmine_issue_repeat/scheduler'

ActiveSupport::Reloader.to_prepare do
  Rails.logger.info("[IssueRepeat] to_prepare: applying IssuePatch")
  RedmineIssueRepeat::IssuePatch.apply
end
