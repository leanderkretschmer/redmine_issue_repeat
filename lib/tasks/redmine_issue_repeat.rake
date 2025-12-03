namespace :redmine_issue_repeat do
  desc 'Process due repeated ticket creations'
  task process: :environment do
    require_relative '../redmine_issue_repeat/scheduler'
    include RedmineIssueRepeat::Scheduler

    cf = IssueCustomField.find_by(name: 'Intervall')
    if cf
      CustomValue.where(customized_type: 'Issue', custom_field_id: cf.id).where.not(value: [nil, '']).pluck(:customized_id).each do |iid|
        issue = Issue.where(id: iid).first
        next unless issue
        interval = interval_value(issue)
        sched = RedmineIssueRepeat::IssueRepeatSchedule.find_or_initialize_by(issue_id: iid)
        if sched.new_record?
          next_run = next_run_for(issue, base_time: Time.current)
          sched.interval = interval if interval
          sched.next_run_at = next_run if next_run
          sched.anchor_day = issue.created_on.day
          if sched.next_run_at && sched.save
            Rails.logger.info("[IssueRepeat] process:init sched=#{sched.id} issue=#{iid} interval=#{sched.interval} next_run_at=#{sched.next_run_at}")
          else
            Rails.logger.info("[IssueRepeat] process:init skipped issue=#{iid} next_run_at missing")
          end
        else
          updates = {}
          updates[:interval] = interval if interval && sched.interval != interval
          updates[:anchor_day] = issue.created_on.day if sched.anchor_day != issue.created_on.day
          # Do NOT move next_run_at forward here; leave due times intact
          if updates.any?
            sched.update!(updates)
            Rails.logger.info("[IssueRepeat] process:update sched=#{sched.id} issue=#{iid} changes=#{updates.inspect}")
          else
            Rails.logger.info("[IssueRepeat] process:skip sched=#{sched.id} issue=#{iid} no changes")
          end
        end
      end
    end

    RedmineIssueRepeat::IssueRepeatSchedule.where('next_run_at <= ?', Time.current).where(active: true).find_each do |sched|
      issue = sched.issue
      unless issue && interval_value(issue)
        sched.update!(active: false)
        Rails.logger.info("[IssueRepeat] process: deactivated sched=#{sched.id} missing interval or issue")
        next
      end

      if issue.closed?
        sched.update!(active: false)
        Rails.logger.info("[IssueRepeat] process: deactivated sched=#{sched.id} issue=#{issue.id} closed")
        next
      end

      interval = interval_value(issue)
      Rails.logger.info("[IssueRepeat] process: sched=#{sched.id} issue=#{issue.id} interval=#{interval} due=#{sched.next_run_at}")
      new_issue = Issue.new
      new_issue.project = issue.project
      new_issue.tracker = issue.tracker
      new_issue.subject = issue.subject
      new_issue.description = issue.description
      new_issue.assigned_to = issue.assigned_to
      new_issue.estimated_hours = issue.estimated_hours
      new_issue.start_date = start_date_for(interval, sched.next_run_at)
      new_issue.status = IssueStatus.default

      cf_id = interval_cf_id(issue)
      new_issue.custom_field_values = { cf_id => nil } if cf_id

      if new_issue.save
        IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
        Rails.logger.info("[IssueRepeat] process: created new_issue=#{new_issue.id} from=#{issue.id} start_date=#{new_issue.start_date}")
        # Compute the following run
        next_time = case interval
                    when 'stündlich'
                      # keep same minute, next hour
                      t = sched.next_run_at + 1.hour
                      minute = (sched.anchor_minute || (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i) % 60
                      Time.new(t.year, t.month, t.day, t.hour, minute, 0, t.utc_offset)
                    when 'täglich'
                      d = (sched.next_run_at + 1.day).to_date
                      h = sched.anchor_hour || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time']).first
                      m = sched.anchor_minute || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time']).last
                      Time.new(d.year, d.month, d.day, h, m, 0, sched.next_run_at.utc_offset)
                    when 'wöchentlich'
                      d = (sched.next_run_at + 7.days).to_date
                      h = sched.anchor_hour || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time']).first
                      m = sched.anchor_minute || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time']).last
                      Time.new(d.year, d.month, d.day, h, m, 0, sched.next_run_at.utc_offset)
                    when 'monatlich'
                      anchor_day = sched.anchor_day || issue.created_on.day
                      d = RedmineIssueRepeat::Scheduler.next_month_date(sched.next_run_at.to_date, anchor_day)
                      # if 31/30 fallback when needed
                      last = Date.civil(d.year, d.month, -1)
                      day = [anchor_day, last.day].min
                      if anchor_day == 31 && last.day == 30 && sched.backup_anchor_day == 30
                        day = 30
                      elsif anchor_day >= 30 && last.day < anchor_day && sched.backup_anchor_day && sched.backup_anchor_day <= last.day
                        day = sched.backup_anchor_day
                      end
                      h = sched.anchor_hour || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time']).first
                      m = sched.anchor_minute || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time']).last
                      Time.new(d.year, d.month, day, h, m, 0, sched.next_run_at.utc_offset)
                    end
        sched.update!(next_run_at: next_time, times_run: (sched.times_run + 1))
        Rails.logger.info("[IssueRepeat] process: rescheduled sched=#{sched.id} next_run_at=#{next_time}")
      else
        Rails.logger.error("[IssueRepeat] process: failed to create copy for issue=#{issue.id}: #{new_issue.errors.full_messages.join(', ')}")
      end
    end
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
        next_run = next_run_for(issue, base_time: Time.current)
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
