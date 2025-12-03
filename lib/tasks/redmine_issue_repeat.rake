namespace :redmine_issue_repeat do
  desc 'Process due repeated ticket creations'
  task process: :environment do
    require_relative '../redmine_issue_repeat/scheduler'
    include RedmineIssueRepeat::Scheduler

    RedmineIssueRepeat::IssueRepeatSchedule.where('next_run_at <= ?', Time.current).find_each do |sched|
      issue = sched.issue
      next unless issue && interval_value(issue)

      interval = interval_value(issue)
      new_issue = Issue.new
      new_issue.project = issue.project
      new_issue.tracker = issue.tracker
      new_issue.subject = issue.subject
      new_issue.description = issue.description
      new_issue.assigned_to = issue.assigned_to
      new_issue.estimated_hours = issue.estimated_hours
      new_issue.start_date = start_date_for(interval, sched.next_run_at)
      new_issue.status = IssueStatus.default

      cf = IssueCustomField.find_by(name: 'Intervall')
      new_issue.custom_field_values = { cf.id => nil } if cf

      if new_issue.save
        IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
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
        val = issue.custom_field_value(cf.id)
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
          sched.update!(updates) unless updates.empty?
        else
          RedmineIssueRepeat::IssueRepeatSchedule.create!(issue_id: issue.id, interval: interval, next_run_at: next_run, anchor_day: issue.created_on.day) if next_run
        end
      end
    end
  end
end

