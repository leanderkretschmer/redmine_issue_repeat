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
    new_issue.subject = issue.subject
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

    # Copy all custom fields except Intervall
    cf_values = {}
    issue.custom_field_values.each do |cv|
      cf_values[cv.custom_field_id] = cv.value
    end
    cf_id = RedmineIssueRepeat::Scheduler.interval_cf_id(issue)
    cf_values[cf_id] = nil if cf_id
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
                  d = (now + 7.days).to_date
                  h = sched.anchor_hour || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time']).first
                  m = sched.anchor_minute || RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time']).last
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
