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

    RedmineIssueRepeat::IssueRepeatSchedule.where('next_run_at <= ?', Time.current).find_each do |sched|
      issue = sched.issue
      next unless issue && interval_value(issue)

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
                      sched.next_run_at + 1.hour
                    when 'täglich'
                      sched.next_run_at + 1.day
                    when 'wöchentlich'
                      sched.next_run_at + 7.days
                    when 'monatlich'
                      anchor_day = issue.created_on.day
                      d = next_month_date(sched.next_run_at.to_date, anchor_day)
                      Time.new(d.year, d.month, d.day, sched.next_run_at.hour, sched.next_run_at.min, 0, sched.next_run_at.utc_offset)
                    end
        sched.update!(next_run_at: next_time)
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
          updates[:anchor_day] = issue.created_on.day if sched.anchor_day != issue.created_on.day
          if updates.empty?
            Rails.logger.info("[IssueRepeat] backfill: no changes for issue=#{issue.id} sched=#{sched.id}")
          else
            sched.update!(updates)
            Rails.logger.info("[IssueRepeat] backfill: updated issue=#{issue.id} sched=#{sched.id} changes=#{updates.inspect}")
          end
        else
          if next_run
            sched_new = RedmineIssueRepeat::IssueRepeatSchedule.create!(issue_id: issue.id, interval: interval, next_run_at: next_run, anchor_day: issue.created_on.day)
            Rails.logger.info("[IssueRepeat] backfill: created sched=#{sched_new.id} issue=#{issue.id} interval=#{interval} next_run_at=#{next_run}")
          else
            Rails.logger.info("[IssueRepeat] backfill: no next_run computed for issue=#{issue.id} interval=#{interval}")
          end
        end
      end
    end
  end
end

