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

      # Stelle sicher, dass das Wochentag-Feld existiert
      cf_weekday = IssueCustomField.find_by(name: 'Intervall Wochentag')
      unless cf_weekday
        cf_weekday = IssueCustomField.new(
          name: 'Intervall Wochentag',
          field_format: 'list',
          possible_values: ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
          is_required: false,
          visible: true,
          editable: true,
          default_value: '',
          multiple: true
        )
        cf_weekday.trackers = Tracker.all
        cf_weekday.save
        Rails.logger.info("[IssueRepeat] Created Custom Field 'Intervall Wochentag'")
      else
        # Stelle sicher, dass multiple auf true gesetzt ist
        if cf_weekday.multiple != true
          cf_weekday.multiple = true
          cf_weekday.save
          Rails.logger.info("[IssueRepeat] Updated 'Intervall Wochentag' field to support multiple selection")
        end
      end

      # Stelle sicher, dass das Monatstag-Feld existiert
      cf_monthday = IssueCustomField.find_by(name: 'Intervall Monatstag')
      unless cf_monthday
        cf_monthday = IssueCustomField.new(
          name: 'Intervall Monatstag',
          field_format: 'list',
          possible_values: ['Anfang des Monats (1.)', 'Ende des Monats (29-31)', 'Mitte des Monats', 'Aktuelles Datum'],
          is_required: false,
          visible: true,
          editable: true,
          default_value: ''
        )
        cf_monthday.trackers = Tracker.all
        cf_monthday.save
        Rails.logger.info("[IssueRepeat] Created Custom Field 'Intervall Monatstag'")
      end

      # Stelle sicher, dass das Intervall Feld die korrekte Sortierung hat (ohne custom)
      cf = IssueCustomField.find_by(name: 'Intervall')
      if cf
        expected_values = ['stündlich', 'täglich', 'wöchentlich', 'monatlich']
        current_values = cf.possible_values || []
        # Entferne 'custom' falls vorhanden
        new_values = current_values.reject { |v| v == 'custom' }
        if new_values != current_values || new_values != expected_values
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
