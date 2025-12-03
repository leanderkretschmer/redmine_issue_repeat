require_relative 'redmine_issue_repeat/issue_patch'
require_relative 'redmine_issue_repeat/scheduler'
require_relative 'redmine_issue_repeat/processor'
require_relative 'redmine_issue_repeat/auto_runner'

ActiveSupport::Reloader.to_prepare do
  RedmineIssueRepeat::IssuePatch.apply
end

Rails.application.config.after_initialize do
  RedmineIssueRepeat::AutoRunner.start
end
