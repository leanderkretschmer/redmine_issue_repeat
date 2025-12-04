require_relative 'redmine_issue_repeat/issue_patch'
require_relative 'redmine_issue_repeat/scheduler'
require_relative 'redmine_issue_repeat/processor'
require_relative 'redmine_issue_repeat/auto_runner'
require_relative 'redmine_issue_repeat/issue_ui'
require_relative 'redmine_issue_repeat/view_hooks'

ActiveSupport::Reloader.to_prepare do
  RedmineIssueRepeat::IssuePatch.apply
end

module RedmineIssueRepeat
  module StatusSetup
    def self.ensure_intervall_status
      status = IssueStatus.find_by(name: 'Ticket geschlossen')
      IssueStatus.create!(name: 'Ticket geschlossen', is_closed: true) unless status
    end
  end
end

Rails.application.config.after_initialize do
  RedmineIssueRepeat::StatusSetup.ensure_intervall_status
  RedmineIssueRepeat::AutoRunner.start
end
