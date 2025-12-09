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
      status = IssueStatus.find_by(name: 'Intervall')
      IssueStatus.create!(name: 'Intervall', is_closed: true) unless status
    end
  end

  module FieldSetup
    def self.ensure_custom_fields
      # Stelle sicher, dass das Intervall Uhrzeit Feld existiert
      cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
      unless cf_time
        cf_time = IssueCustomField.new(
          name: 'Intervall Uhrzeit',
          field_format: 'string',
          is_required: false,
          visible: true,
          editable: true,
          default_value: '',
          regexp: '^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$'
        )
        cf_time.trackers = Tracker.all
        cf_time.save
        Rails.logger.info("[IssueRepeat] Created Custom Field 'Intervall Uhrzeit'")
      end

      # Stelle sicher, dass das Intervall Feld die korrekte Sortierung hat
      cf = IssueCustomField.find_by(name: 'Intervall')
      if cf
        expected_values = ['stündlich', 'täglich', 'wöchentlich', 'monatlich', 'custom']
        if cf.possible_values != expected_values
          cf.possible_values = expected_values
          cf.save
          Rails.logger.info("[IssueRepeat] Updated Custom Field 'Intervall' with correct sorting")
        end
      end
    rescue => e
      Rails.logger.error("[IssueRepeat] Error ensuring custom fields: #{e.message}")
    end
  end
end

Rails.application.config.after_initialize do
  RedmineIssueRepeat::StatusSetup.ensure_intervall_status
  RedmineIssueRepeat::FieldSetup.ensure_custom_fields
  RedmineIssueRepeat::AutoRunner.start
end
