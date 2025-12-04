module RedmineIssueRepeat
  module Processor
    module_function

    def run_once
      require_relative 'scheduler'
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
        base_time = Time.current
        next_run = Scheduler.next_run_for(issue, base_time: base_time)
        if sched.new_record?
          anchor_hour = nil
          anchor_minute = nil
          anchor_day = nil
          backup_anchor_day = nil
          case interval
          when 'stündlich'
            anchor_minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
          when 'täglich'
            h, m = Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time'])
            anchor_hour, anchor_minute = h, m
          when 'wöchentlich'
            h, m = Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time'])
            anchor_hour, anchor_minute = h, m
            anchor_day = issue.created_on.to_date.cwday
          when 'monatlich'
            h, m = Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time'])
            anchor_hour, anchor_minute = h, m
            anchor_day = issue.created_on.day
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
          end
        else
          updates = {}
          updates[:interval] = interval if sched.interval != interval
          case interval
          when 'stündlich'
            minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
            updates[:anchor_minute] = minute if sched.anchor_minute != minute
          when 'täglich'
            h, m = Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time'])
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
          when 'wöchentlich'
            h, m = Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time'])
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
            wday = issue.created_on.to_date.cwday
            updates[:anchor_day] = wday if sched.anchor_day != wday
          when 'monatlich'
            h, m = Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time'])
            updates[:anchor_hour] = h if sched.anchor_hour != h
            updates[:anchor_minute] = m if sched.anchor_minute != m
            day = issue.created_on.day
            updates[:anchor_day] = day if sched.anchor_day != day
            backup = (day == 31 ? 30 : (day == 30 ? 29 : nil))
            updates[:backup_anchor_day] = backup if sched.backup_anchor_day != backup
          end
          updates[:active] = true if sched.active != true
          sched.update!(updates) if updates.any?
        end
      end
    end

    def process_due
      require_relative 'scheduler'
      RedmineIssueRepeat::IssueRepeatSchedule.where('next_run_at <= ?', Time.current).where(active: true).find_each do |sched|
        issue = sched.issue
        unless issue && Scheduler.interval_value(issue)
          sched.update!(active: false)
          next
        end
        if issue.closed?
          sched.update!(active: false)
          next
        end
        interval = Scheduler.interval_value(issue)
        new_issue = Issue.new
        new_issue.project = issue.project
        new_issue.tracker = issue.tracker
        new_issue.subject = issue.subject
        new_issue.description = issue.description
        new_issue.assigned_to = issue.assigned_to
        new_issue.author = issue.author
        new_issue.priority = issue.priority
        new_issue.category = issue.category
        new_issue.fixed_version = issue.fixed_version
        new_issue.due_date = issue.due_date
        new_issue.estimated_hours = issue.estimated_hours
        new_issue.start_date = Scheduler.start_date_for(interval, sched.next_run_at)
        new_issue.status = (IssueStatus.where(is_closed: false).order(:id).first || IssueStatus.order(:id).first)
        # Copy custom fields, but clear Intervall to avoid loops
        cf_values = {}
        issue.custom_field_values.each do |cv|
          cf_values[cv.custom_field_id] = cv.value
        end
        cf_id = Scheduler.interval_cf_id(issue)
        cf_values[cf_id] = nil if cf_id
        new_issue.custom_field_values = cf_values if cf_values.any?

        next_time = case interval
                    when 'stündlich'
                      t = sched.next_run_at + 1.hour
                      minute = (sched.anchor_minute || (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i) % 60
                      Time.new(t.year, t.month, t.day, t.hour, minute, 0, t.utc_offset)
                    when 'täglich'
                      d = (sched.next_run_at + 1.day).to_date
                      h = sched.anchor_hour || Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time']).first
                      m = sched.anchor_minute || Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time']).last
                      Time.new(d.year, d.month, d.day, h, m, 0, sched.next_run_at.utc_offset)
                    when 'wöchentlich'
                      d = (sched.next_run_at + 7.days).to_date
                      h = sched.anchor_hour || Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time']).first
                      m = sched.anchor_minute || Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time']).last
                      Time.new(d.year, d.month, d.day, h, m, 0, sched.next_run_at.utc_offset)
                    when 'monatlich'
                      anchor_day = sched.anchor_day || issue.created_on.day
                      d = Scheduler.next_month_date(sched.next_run_at.to_date, anchor_day)
                      last = Date.civil(d.year, d.month, -1)
                      day = [anchor_day, last.day].min
                      if anchor_day == 31 && last.day == 30 && sched.backup_anchor_day == 30
                        day = 30
                      elsif anchor_day >= 30 && last.day < anchor_day && sched.backup_anchor_day && sched.backup_anchor_day <= last.day
                        day = sched.backup_anchor_day
                      end
                      h = sched.anchor_hour || Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time']).first
                      m = sched.anchor_minute || Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time']).last
                      Time.new(d.year, d.month, day, h, m, 0, sched.next_run_at.utc_offset)
                    end

        if new_issue.save
          IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
          RedmineIssueRepeat::IssueRepeatSchedule.where(id: sched.id).update_all(next_run_at: next_time, times_run: (sched.times_run + 1))
        end
      end
    end
  end
end
