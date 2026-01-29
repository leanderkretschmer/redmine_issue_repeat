namespace :redmine_issue_repeat do
  desc 'Process due repeated ticket creations'
  task process: :environment do
    require_relative '../redmine_issue_repeat/processor'

    RedmineIssueRepeat::Processor.run_once
  end

  desc 'Erstelle oder aktualisiere Custom Fields für Intervall und Intervall Uhrzeit'
  task setup_fields: :environment do
    puts "Erstelle/aktualisiere Custom Fields..."
    
    # Erstelle oder aktualisiere Intervall Uhrzeit Feld
    cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
    if cf_time
      puts "Custom Field 'Intervall Uhrzeit' existiert bereits, aktualisiere..."
      cf_time.field_format = 'string'
      cf_time.is_required = false
      cf_time.visible = true
      cf_time.editable = true
      cf_time.default_value = ''
      cf_time.regexp = '^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$'
      cf_time.trackers = Tracker.all unless cf_time.trackers.any?
      cf_time.save!
      puts "Custom Field 'Intervall Uhrzeit' aktualisiert."
    else
      puts "Erstelle Custom Field 'Intervall Uhrzeit'..."
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
      cf_time.save!
      puts "Custom Field 'Intervall Uhrzeit' erstellt (ID: #{cf_time.id})."
    end

    # Erstelle oder aktualisiere Wochentag-Feld
    cf_weekday = IssueCustomField.find_by(name: 'Intervall Wochentag')
    if cf_weekday
      puts "Custom Field 'Intervall Wochentag' existiert bereits, aktualisiere..."
      cf_weekday.field_format = 'list'
      cf_weekday.possible_values = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag']
      cf_weekday.is_required = false
      cf_weekday.visible = true
      cf_weekday.editable = true
      cf_weekday.default_value = ''
      cf_weekday.multiple = true
      cf_weekday.trackers = Tracker.all unless cf_weekday.trackers.any?
      cf_weekday.save!
      puts "Custom Field 'Intervall Wochentag' aktualisiert (Multi-Select aktiviert)."
    else
      puts "Erstelle Custom Field 'Intervall Wochentag'..."
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
      cf_weekday.save!
      puts "Custom Field 'Intervall Wochentag' erstellt (ID: #{cf_weekday.id}, Multi-Select aktiviert)."
    end

    # Erstelle oder aktualisiere Monatstag-Feld
    cf_monthday = IssueCustomField.find_by(name: 'Intervall Monatstag')
    if cf_monthday
      puts "Custom Field 'Intervall Monatstag' existiert bereits, aktualisiere..."
      cf_monthday.field_format = 'list'
      cf_monthday.possible_values = ['Anfang des Monats (1.)', 'Ende des Monats (29-31)', 'Mitte des Monats', 'Aktuelles Datum']
      cf_monthday.is_required = false
      cf_monthday.visible = true
      cf_monthday.editable = true
      cf_monthday.default_value = ''
      cf_monthday.trackers = Tracker.all unless cf_monthday.trackers.any?
      cf_monthday.save!
      puts "Custom Field 'Intervall Monatstag' aktualisiert."
    else
      puts "Erstelle Custom Field 'Intervall Monatstag'..."
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
      cf_monthday.save!
      puts "Custom Field 'Intervall Monatstag' erstellt (ID: #{cf_monthday.id})."
    end

    # Aktualisiere Intervall-Feld mit korrekter Sortierung (ohne custom)
    cf = IssueCustomField.find_by(name: 'Intervall')
    if cf
      puts "Aktualisiere Custom Field 'Intervall' mit korrekter Sortierung..."
      current_values = cf.possible_values || []
      new_values = current_values.reject { |v| v == 'custom' }
      if new_values != ['stündlich', 'täglich', 'wöchentlich', 'monatlich']
        cf.possible_values = ['stündlich', 'täglich', 'wöchentlich', 'monatlich']
        cf.save!
        puts "Custom Field 'Intervall' aktualisiert (custom entfernt)."
      else
        puts "Custom Field 'Intervall' bereits korrekt konfiguriert."
      end
    else
      puts "WARNUNG: Custom Field 'Intervall' nicht gefunden!"
    end
    
    puts "Fertig!"
  end

  desc 'Backfill schedules for issues with Intervall set'
  task backfill_schedules: :environment do
    require_relative '../redmine_issue_repeat/scheduler'
    include RedmineIssueRepeat::Scheduler

    cf = IssueCustomField.find_by(name: 'Intervall')
    if cf
      Issue.all.find_each do |issue|
        val = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf.id).limit(1).pluck(:value).first
        next if val.nil? || val.to_s.strip.empty?

        interval = interval_value(issue)
        next unless interval

        sched = RedmineIssueRepeat::IssueRepeatSchedule.find_by(issue_id: issue.id)
        next_run = next_run_for(issue, base_time: Scheduler.now_in_zone)
        if sched
          updates = {}
          updates[:interval] = interval if sched.interval != interval
          updates[:next_run_at] = next_run if next_run
          case interval
          when 'stündlich'
            minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
            updates[:anchor_minute] = minute if sched.anchor_minute != minute
          when 'täglich'
            h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time'])
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
          when 'wöchentlich'
            h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time'])
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
            wday = issue.created_on.to_date.cwday
            updates[:anchor_day] = wday if sched.anchor_day != wday
          when 'monatlich'
            h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time'])
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
            day = issue.created_on.day
            updates[:anchor_day] = day if sched.anchor_day != day
            backup = (day == 31 ? 30 : (day == 30 ? 29 : nil))
            updates[:backup_anchor_day] = backup if sched.backup_anchor_day != backup
          end
          updates[:active] = true if sched.active != true
          if updates.empty?
            Rails.logger.info("[IssueRepeat] backfill: no changes for issue=#{issue.id} sched=#{sched.id}")
          else
            sched.update!(updates)
            Rails.logger.info("[IssueRepeat] backfill: updated issue=#{issue.id} sched=#{sched.id} changes=#{updates.inspect}")
          end
        else
          if next_run
            anchor_hour = nil
            anchor_minute = nil
            anchor_day = nil
            backup_anchor_day = nil
            case interval
            when 'stündlich'
              anchor_minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
            when 'täglich'
              h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time'])
              anchor_hour, anchor_minute = h, m
            when 'wöchentlich'
              h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time'])
              anchor_hour, anchor_minute = h, m
              anchor_day = issue.created_on.to_date.cwday
            when 'monatlich'
              h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time'])
              anchor_hour, anchor_minute = h, m
              anchor_day = issue.created_on.day
              backup_anchor_day = (anchor_day == 31 ? 30 : (anchor_day == 30 ? 29 : nil))
            end
            sched_new = RedmineIssueRepeat::IssueRepeatSchedule.create!(issue_id: issue.id, interval: interval, next_run_at: next_run, anchor_day: anchor_day, anchor_hour: anchor_hour, anchor_minute: anchor_minute, backup_anchor_day: backup_anchor_day, active: true, times_run: 0)
            Rails.logger.info("[IssueRepeat] backfill: created sched=#{sched_new.id} issue=#{issue.id} interval=#{interval} next_run_at=#{next_run}")
          else
            Rails.logger.info("[IssueRepeat] backfill: no next_run computed for issue=#{issue.id} interval=#{interval}")
          end
        end
      end
    end
  end
end
