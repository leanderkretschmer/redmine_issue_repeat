require_relative 'redmine_issue_repeat/issue_patch'

ActiveSupport::Reloader.to_prepare do
  RedmineIssueRepeat::IssuePatch.apply
end

