module RedmineIssueRepeat
  module Processor
    module_function

    def run_once
      require_relative 'scheduler'
      require_relative 'checklist_copy'
      init_schedules
      process_due
    end

    def init_schedules
      cf = IssueCustomField.find_by(name: 'Intervall')
      return unless cf
      CustomValue.where(customized_type: 'Issue', custom_field_id: cf.id).where.not(value: [nil, '']).pluck(:customized_id).each do |iid|
        issue = Issue.where(id: iid).first
        next unless issue
        interval = Scheduler.interval_value(issue)
        next unless interval
        sched = RedmineIssueRepeat::IssueRepeatSchedule.find_or_initialize_by(issue_id: iid)
        base_time = Scheduler.now_in_zone
        next_run = Scheduler.next_run_for(issue, base_time: base_time)
        if sched.new_record?
          anchor_hour = nil
          anchor_minute = nil
          anchor_day = nil
          backup_anchor_day = nil
          case interval
          when 'stündlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden (nur Minute wird verwendet)
            custom_time = Scheduler.custom_time_for_issue(issue)
            if custom_time
              _, m = Scheduler.parse_time(custom_time)
              anchor_minute = m
            else
              anchor_minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
            end
          when 'täglich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            custom_time = Scheduler.custom_time_for_issue(issue)
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['daily_time']
            h, m = Scheduler.parse_time(time_str)
            anchor_hour, anchor_minute = h, m
          when 'wöchentlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            custom_time = Scheduler.custom_time_for_issue(issue)
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['weekly_time']
            h, m = Scheduler.parse_time(time_str)
            anchor_hour, anchor_minute = h, m
            # Verwende ausgewählte Wochentage falls vorhanden, sonst Tag der Erstellung
            weekday_names = Scheduler.weekdays_for_issue(issue)
            if weekday_names.any?
              # Nimm den ersten Wochentag als anchor_day (wird für next_run verwendet)
              anchor_day = Scheduler.weekday_name_to_number(weekday_names.first)
            else
              anchor_day = issue.created_on.to_date.cwday
            end
          when 'monatlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            custom_time = Scheduler.custom_time_for_issue(issue)
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['monthly_time']
            h, m = Scheduler.parse_time(time_str)
            anchor_hour, anchor_minute = h, m
            # Verwende Monatstag-Option falls vorhanden
            monthday_option = Scheduler.monthday_option_for_issue(issue)
            if monthday_option
              # Berechne Tag basierend auf Option (für ersten Monat)
              next_month_date = issue.created_on.to_date.next_month
              anchor_day = Scheduler.calculate_month_day(monthday_option, issue.created_on.day, next_month_date)
            else
              anchor_day = issue.created_on.day
            end
            backup_anchor_day = (anchor_day == 31 ? 30 : (anchor_day == 30 ? 29 : nil))
          end
        if next_run
            sched.interval = interval
            sched.next_run_at = next_run
            sched.anchor_day = anchor_day
            sched.anchor_hour = anchor_hour
            sched.anchor_minute = anchor_minute
            sched.backup_anchor_day = backup_anchor_day
            sched.active = true
            sched.times_run = 0
            sched.save
          begin
            RedmineIssueRepeat::EntrySync.sync_schedule(sched)
          rescue => e
            Rails.logger.error("[IssueRepeat] entry_sync save error: #{e.class} #{e.message}")
          end
          end
        else
          updates = {}
          updates[:interval] = interval if sched.interval != interval
          case interval
          when 'stündlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden (nur Minute wird verwendet)
            custom_time = Scheduler.custom_time_for_issue(issue)
            if custom_time
              _, m = Scheduler.parse_time(custom_time)
              minute = m
            else
              minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
            end
            updates[:anchor_minute] = minute if sched.anchor_minute != minute
          when 'täglich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            custom_time = Scheduler.custom_time_for_issue(issue)
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['daily_time']
            h, m = Scheduler.parse_time(time_str)
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
          when 'wöchentlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            custom_time = Scheduler.custom_time_for_issue(issue)
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['weekly_time']
            h, m = Scheduler.parse_time(time_str)
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
            # Verwende ausgewählte Wochentage falls vorhanden, sonst Tag der Erstellung
            weekday_names = Scheduler.weekdays_for_issue(issue)
            if weekday_names.any?
              # Nimm den ersten Wochentag als anchor_day (wird für next_run verwendet)
              wday = Scheduler.weekday_name_to_number(weekday_names.first)
            else
              wday = issue.created_on.to_date.cwday
            end
            updates[:anchor_day] = wday if sched.anchor_day != wday
          when 'monatlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            custom_time = Scheduler.custom_time_for_issue(issue)
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['monthly_time']
            h, m = Scheduler.parse_time(time_str)
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
            # Verwende Monatstag-Option falls vorhanden
            monthday_option = Scheduler.monthday_option_for_issue(issue)
            if monthday_option
              # Berechne Tag basierend auf Option (für nächsten Monat)
              next_month_date = Time.current.to_date.next_month
              day = Scheduler.calculate_month_day(monthday_option, issue.created_on.day, next_month_date)
            else
              day = issue.created_on.day
            end
            updates[:anchor_day] = day if sched.anchor_day != day
            backup = (day == 31 ? 30 : (day == 30 ? 29 : nil))
            updates[:backup_anchor_day] = backup if sched.backup_anchor_day != backup
          end
          updates[:active] = true if sched.active != true
          sched.update!(updates) if updates.any?
          begin
            RedmineIssueRepeat::EntrySync.sync_schedule(sched)
          rescue => e
            Rails.logger.error("[IssueRepeat] entry_sync update error: #{e.class} #{e.message}")
          end
        end
      end
    end

    def process_due
      require_relative 'scheduler'
      intervall_status_id = IssueStatus.where(name: 'Intervall').pluck(:id).first
      RedmineIssueRepeat::IssueRepeatSchedule.where('next_run_at <= ?', Time.now.to_i).where(active: true).find_each do |sched|
        issue = sched.issue
        unless issue && Scheduler.interval_value(issue)
          sched.update!(active: false)
          next
        end
        if issue.closed? && issue.status_id != intervall_status_id
          sched.update!(active: false)
          next
        end
        interval = Scheduler.interval_value(issue)
        new_issue = Issue.new
        new_issue.project = issue.project
        new_issue.tracker = issue.tracker
        new_issue.subject = Scheduler.add_prefix_to_subject(issue.subject)
        new_issue.description = issue.description
        new_issue.assigned_to = issue.assigned_to
        new_issue.author = issue.author
        new_issue.priority = issue.priority
        new_issue.category = issue.category
        new_issue.fixed_version = issue.fixed_version
        new_issue.due_date = issue.due_date
        new_issue.estimated_hours = issue.estimated_hours
        new_issue.start_date = Scheduler.start_date_for(interval, Scheduler.time_from_epoch(sched.next_run_at))
        if new_issue.due_date && new_issue.start_date && new_issue.start_date > new_issue.due_date
          new_issue.due_date = new_issue.start_date
        end
        new_issue.status = (IssueStatus.where(is_closed: false).order(:id).first || IssueStatus.order(:id).first)
        # Copy custom fields, but exclude all Intervall-related fields to avoid loops
        cf_values = {}
        excluded_ids = Scheduler.interval_related_cf_ids
        issue.custom_field_values.each do |cv|
          next if excluded_ids.include?(cv.custom_field_id)
          cf_values[cv.custom_field_id] = cv.value
        end
        new_issue.custom_field_values = cf_values if cf_values.any?

        next_time = case interval
                    when 'stündlich'
                      t = Scheduler.time_from_epoch(sched.next_run_at) + 1.hour
                      # Verwende gespeicherte Anchor-Minute oder pro-Ticket-Uhrzeit oder Standard
                      if sched.anchor_minute
                        minute = sched.anchor_minute % 60
                      else
                        custom_time = Scheduler.custom_time_for_issue(issue)
                        if custom_time
                          _, m = Scheduler.parse_time(custom_time)
                          minute = m % 60
                        else
                          minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i % 60
                        end
                      end
                      Time.new(t.year, t.month, t.day, t.hour, minute, 0, Scheduler.utc_offset_seconds).to_i
                    when 'täglich'
                      d = (Scheduler.time_from_epoch(sched.next_run_at) + 1.day).to_date
                      # Verwende gespeicherte Anchor-Werte oder pro-Ticket-Uhrzeit oder Standard
                      h = sched.anchor_hour
                      m = sched.anchor_minute
                      if h.nil? || m.nil?
                        custom_time = Scheduler.custom_time_for_issue(issue)
                        time_str = custom_time || Setting.plugin_redmine_issue_repeat['daily_time']
                        h, m = Scheduler.parse_time(time_str)
                      end
                      Time.new(d.year, d.month, d.day, h, m, 0, Scheduler.utc_offset_seconds).to_i
                    when 'wöchentlich'
                      # Verwende gespeicherte Anchor-Werte oder pro-Ticket-Uhrzeit oder Standard
                      h = sched.anchor_hour
                      m = sched.anchor_minute
                      if h.nil? || m.nil?
                        custom_time = Scheduler.custom_time_for_issue(issue)
                        time_str = custom_time || Setting.plugin_redmine_issue_repeat['weekly_time']
                        h, m = Scheduler.parse_time(time_str)
                      end
                      # Verwende ausgewählte Wochentage falls vorhanden
                      weekday_names = Scheduler.weekdays_for_issue(issue)
                      if weekday_names.any?
                        # Konvertiere Wochentagsnamen zu Nummern
                        target_weekdays = weekday_names.map { |name| Scheduler.weekday_name_to_number(name) }.compact
                        if target_weekdays.any?
                          # Finde nächsten passenden Wochentag
                          current_weekday = Scheduler.time_from_epoch(sched.next_run_at).to_date.cwday
                          days_ahead = nil
                          target_weekdays.sort.each do |target_weekday|
                            diff = target_weekday - current_weekday
                            diff += 7 if diff <= 0
                            days_ahead = diff if days_ahead.nil? || diff < days_ahead
                          end
                          # Falls kein Tag in dieser Woche gefunden wurde, nimm den ersten der nächsten Woche
                          days_ahead ||= (target_weekdays.min - current_weekday) + 7
                          d = Scheduler.time_from_epoch(sched.next_run_at).to_date + days_ahead
                        else
                          d = Scheduler.time_from_epoch(sched.next_run_at).to_date + 7
                        end
                      else
                        # Fallback: Verwende gespeicherten Wochentag oder Tag der Erstellung
                        target_weekday = sched.anchor_day || issue.created_on.to_date.cwday
                        current_weekday = Scheduler.time_from_epoch(sched.next_run_at).to_date.cwday
                        days_ahead = target_weekday - current_weekday
                        days_ahead += 7 if days_ahead <= 0
                        d = Scheduler.time_from_epoch(sched.next_run_at).to_date + days_ahead
                      end
                      Time.new(d.year, d.month, d.day, h, m, 0, Scheduler.utc_offset_seconds).to_i
                    when 'monatlich'
                      # Berechne nächsten Monat
                      d = Scheduler.time_from_epoch(sched.next_run_at).to_date.next_month
                      
                      # Verwende Monatstag-Option falls vorhanden
                      monthday_option = Scheduler.monthday_option_for_issue(issue)
                      if monthday_option
                        day = Scheduler.calculate_month_day(monthday_option, issue.created_on.day, d)
                      else
                        # Fallback: Gespeicherter Tag oder Tag der Erstellung
                        anchor_day = sched.anchor_day || issue.created_on.day
                        last = Date.civil(d.year, d.month, -1)
                        day = [anchor_day, last.day].min
                        if anchor_day == 31 && last.day == 30 && sched.backup_anchor_day == 30
                          day = 30
                        elsif anchor_day >= 30 && last.day < anchor_day && sched.backup_anchor_day && sched.backup_anchor_day <= last.day
                          day = sched.backup_anchor_day
                        end
                      end
                      
                      # Verwende gespeicherte Anchor-Werte oder pro-Ticket-Uhrzeit oder Standard
                      h = sched.anchor_hour
                      m = sched.anchor_minute
                      if h.nil? || m.nil?
                        custom_time = Scheduler.custom_time_for_issue(issue)
                        time_str = custom_time || Setting.plugin_redmine_issue_repeat['monthly_time']
                        h, m = Scheduler.parse_time(time_str)
                      end
                      Time.new(d.year, d.month, day, h, m, 0, Scheduler.utc_offset_seconds).to_i
                    else
                      nil
                    end

        if new_issue.save
          IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
          RedmineIssueRepeat::ChecklistCopy.copy_from(issue, new_issue)
          prev_run = sched.next_run_at
          RedmineIssueRepeat::IssueRepeatSchedule.where(id: sched.id).update_all(next_run_at: next_time, times_run: (sched.times_run + 1))
          begin
            if RedmineIssueRepeat::EntrySync.table_exists?
              entry = RedmineIssueRepeat::IssueRepeatEntry.find_or_initialize_by(ticket_id: issue.id)
              entry.ticket_title = issue.subject
              entry.intervall = interval
              entry.intervall_hour = sched.anchor_hour
              entry.intervall_weekday = RedmineIssueRepeat::Scheduler.weekdays_for_issue(issue).presence&.to_json
              if interval == 'monatlich'
                opt = RedmineIssueRepeat::Scheduler.monthday_option_for_issue(issue)
                if opt
                  target_date = RedmineIssueRepeat::Scheduler.time_from_epoch(next_time).to_date
                  entry.intervall_monthday = RedmineIssueRepeat::Scheduler.calculate_month_day(opt, issue.created_on.day, target_date)
                else
                  entry.intervall_monthday = sched.anchor_day
                end
              else
                entry.intervall_monthday = nil
              end
              entry.intervall_state = IssueStatus.find_by(id: issue.status_id)&.name == 'Intervall'
              entry.last_changed = issue.updated_on.to_i
              entry.last_run = prev_run
              entry.times_run = sched.times_run + 1
              entry.next_run = next_time
              entry.save!
            end
          rescue => e
            Rails.logger.error("[IssueRepeat] entry_sync process error: #{e.class} #{e.message}")
          end
        end
      end
    end
  end
end
