class RedmineIssueRepeat::ActionsController < ApplicationController
  def repeat_now
    issue = Issue.find_by(id: params[:id])
    return redirect_to settings_path unless issue

    interval = RedmineIssueRepeat::Scheduler.interval_value(issue)
    return redirect_to settings_path unless interval

    sched = RedmineIssueRepeat::IssueRepeatSchedule.find_or_initialize_by(issue_id: issue.id)
    now = Time.current

    new_issue = Issue.new
    new_issue.project = issue.project
    new_issue.tracker = issue.tracker
    new_issue.subject = RedmineIssueRepeat::Scheduler.add_prefix_to_subject(issue.subject)
    new_issue.description = issue.description
    new_issue.assigned_to = issue.assigned_to
    new_issue.author = issue.author
    new_issue.priority = issue.priority
    new_issue.category = issue.category
    new_issue.fixed_version = issue.fixed_version
    new_issue.due_date = issue.due_date
    new_issue.estimated_hours = issue.estimated_hours
    new_issue.start_date = RedmineIssueRepeat::Scheduler.start_date_for(interval, now)
    new_issue.status = (IssueStatus.where(is_closed: false).order(:id).first || IssueStatus.order(:id).first)

    # Copy all custom fields except all Intervall-related fields
    cf_values = {}
    excluded_ids = RedmineIssueRepeat::Scheduler.interval_related_cf_ids
    issue.custom_field_values.each do |cv|
      next if excluded_ids.include?(cv.custom_field_id)
      cf_values[cv.custom_field_id] = cv.value
    end
    new_issue.custom_field_values = cf_values if cf_values.any?

    next_time = case interval
                when 'stündlich'
                  t = now + 1.hour
                  minute = (sched.anchor_minute || (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i) % 60
                  Time.new(t.year, t.month, t.day, t.hour, minute, 0, t.utc_offset)
                when 'täglich'
                  d = (now + 1.day).to_date
                  h = sched.anchor_hour || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time']).first
                  m = sched.anchor_minute || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time']).last
                  Time.new(d.year, d.month, d.day, h, m, 0, now.utc_offset)
                when 'wöchentlich'
                  # Verwende pro-Ticket-Uhrzeit falls vorhanden, sonst Standard
                  custom_time = RedmineIssueRepeat::Scheduler.custom_time_for_issue(issue)
                  time_str = custom_time || Setting.plugin_redmine_issue_repeat['weekly_time']
                  h = sched.anchor_hour || RedmineIssueRepeat::Scheduler.parse_time(time_str).first
                  m = sched.anchor_minute || RedmineIssueRepeat::Scheduler.parse_time(time_str).last
                  
                  # Verwende ausgewählte Wochentage falls vorhanden
                  weekday_names = RedmineIssueRepeat::Scheduler.weekdays_for_issue(issue)
                  if weekday_names.any?
                    # Konvertiere Wochentagsnamen zu Nummern
                    target_weekdays = weekday_names.map { |name| RedmineIssueRepeat::Scheduler.weekday_name_to_number(name) }.compact
                    if target_weekdays.any?
                      # Finde nächsten passenden Wochentag
                      current_weekday = now.to_date.cwday
                      days_ahead = nil
                      target_weekdays.sort.each do |target_weekday|
                        diff = target_weekday - current_weekday
                        diff += 7 if diff <= 0
                        days_ahead = diff if days_ahead.nil? || diff < days_ahead
                      end
                      # Falls kein Tag in dieser Woche gefunden wurde, nimm den ersten der nächsten Woche
                      days_ahead ||= (target_weekdays.min - current_weekday) + 7
                      d = now.to_date + days_ahead
                    else
                      d = (now + 7.days).to_date
                    end
                  else
                    d = (now + 7.days).to_date
                  end
                  Time.new(d.year, d.month, d.day, h, m, 0, now.utc_offset)
                when 'monatlich'
                  anchor_day = sched.anchor_day || issue.created_on.day
                  d = RedmineIssueRepeat::Scheduler.next_month_date(now.to_date, anchor_day)
                  last = Date.civil(d.year, d.month, -1)
                  day = [anchor_day, last.day].min
                  if anchor_day == 31 && last.day == 30 && sched.backup_anchor_day == 30
                    day = 30
                  elsif anchor_day >= 30 && last.day < anchor_day && sched.backup_anchor_day && sched.backup_anchor_day <= last.day
                    day = sched.backup_anchor_day
                  end
                  h = sched.anchor_hour || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time']).first
                  m = sched.anchor_minute || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time']).last
                  Time.new(d.year, d.month, day, h, m, 0, now.utc_offset)
                end

    if new_issue.due_date && new_issue.start_date && new_issue.start_date > new_issue.due_date
      new_issue.due_date = new_issue.start_date
    end

    if new_issue.save
      IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
      RedmineIssueRepeat::IssueRepeatSchedule.where(issue_id: issue.id).update_all(next_run_at: next_time, active: true, times_run: (sched.times_run || 0) + 1)
      flash[:notice] = "Kopie erstellt: ##{new_issue.id}"
    else
      flash[:error] = new_issue.errors.full_messages.join(', ')
    end

    redirect_to settings_path
  end
end
