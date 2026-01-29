module RedmineIssueRepeat
  module EntrySync
    module_function

    def table_exists?
      ActiveRecord::Base.connection.table_exists?('issue_repeat_entries')
    end

    def sync_schedule(sched)
      return unless table_exists?
      issue = sched.issue
      return unless issue
      interval = RedmineIssueRepeat::Scheduler.interval_value(issue)
      return unless interval
      weekday_names = RedmineIssueRepeat::Scheduler.weekdays_for_issue(issue)
      monthday_option = RedmineIssueRepeat::Scheduler.monthday_option_for_issue(issue)
      monthday = if interval == 'monatlich'
        if monthday_option
          target_date = RedmineIssueRepeat::Scheduler.time_from_epoch(sched.next_run_at).to_date
          RedmineIssueRepeat::Scheduler.calculate_month_day(monthday_option, issue.created_on.day, target_date)
        else
          sched.anchor_day
        end
      else
        nil
      end
      hour = sched.anchor_hour
      state = IssueStatus.find_by(id: issue.status_id)&.name == 'Intervall'
      last_changed = issue.updated_on.to_i
      entry = RedmineIssueRepeat::IssueRepeatEntry.find_or_initialize_by(ticket_id: issue.id)
      entry.ticket_title = issue.subject
      entry.intervall = interval
      entry.intervall_hour = hour
      entry.intervall_weekday = weekday_names.any? ? weekday_names.to_json : nil
      entry.intervall_monthday = monthday
      entry.intervall_state = state
      entry.last_changed = last_changed
      entry.last_run = entry.last_run
      entry.times_run = sched.times_run
      entry.next_run = sched.next_run_at
      entry.save!
    end

    def sync_all
      return unless table_exists?
      return unless RedmineIssueRepeat::IssueRepeatSchedule.table_exists?
      RedmineIssueRepeat::IssueRepeatSchedule.find_each do |sched|
        sync_schedule(sched)
      end
    end
  end
end
