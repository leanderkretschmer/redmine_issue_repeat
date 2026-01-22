class RedmineIssueRepeat::RepeatsController < ApplicationController
  before_action :require_admin

  def repeat_now
    sched = RedmineIssueRepeat::IssueRepeatSchedule.find(params[:id])
    issue = sched.issue
    interval = RedmineIssueRepeat::Scheduler.interval_value(issue)
    return render_404 unless issue && interval
    Rails.logger.info("[IssueRepeat] repeat_now: sched=#{sched.id} issue=#{issue.id} interval=#{interval}")

    new_issue = Issue.new
    new_issue.project = issue.project
    new_issue.tracker = issue.tracker
    new_issue.subject = RedmineIssueRepeat::Scheduler.add_prefix_to_subject(issue.subject)
    new_issue.description = issue.description
    new_issue.assigned_to = issue.assigned_to
    new_issue.estimated_hours = issue.estimated_hours
    new_issue.start_date = RedmineIssueRepeat::Scheduler.start_date_for(interval, Time.current)
    new_issue.status = IssueStatus.default

    # Copy all custom fields except all Intervall-related fields
    cf_values = {}
    excluded_ids = RedmineIssueRepeat::Scheduler.interval_related_cf_ids
    issue.custom_field_values.each do |cv|
      next if excluded_ids.include?(cv.custom_field_id)
      cf_values[cv.custom_field_id] = cv.value
    end
    new_issue.custom_field_values = cf_values if cf_values.any?

    if new_issue.save
      IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
      RedmineIssueRepeat::ChecklistCopy.copy_from(issue, new_issue)
      next_run = RedmineIssueRepeat::Scheduler.next_run_for(issue, base_time: Time.current)
      sched.update!(next_run_at: next_run) if next_run
      Rails.logger.info("[IssueRepeat] repeat_now: created new_issue=#{new_issue.id} from=#{issue.id} next_run_at=#{next_run}")
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = new_issue.errors.full_messages.join(', ')
      Rails.logger.error("[IssueRepeat] repeat_now: failed to create copy for issue=#{issue.id}: #{new_issue.errors.full_messages.join(', ')}")
    end

    redirect_back fallback_location: home_path
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def repeat_now_issue
    issue = Issue.find(params[:id])
    interval = RedmineIssueRepeat::Scheduler.interval_value(issue)
    return render_404 unless issue && interval
    Rails.logger.info("[IssueRepeat] repeat_now_issue: issue=#{issue.id} interval=#{interval}")

    new_issue = Issue.new
    new_issue.project = issue.project
    new_issue.tracker = issue.tracker
    new_issue.subject = RedmineIssueRepeat::Scheduler.add_prefix_to_subject(issue.subject)
    new_issue.description = issue.description
    new_issue.assigned_to = issue.assigned_to
    new_issue.estimated_hours = issue.estimated_hours
    new_issue.start_date = RedmineIssueRepeat::Scheduler.start_date_for(interval, Time.current)
    new_issue.status = IssueStatus.default

    # Copy all custom fields except all Intervall-related fields
    cf_values = {}
    excluded_ids = RedmineIssueRepeat::Scheduler.interval_related_cf_ids
    issue.custom_field_values.each do |cv|
      next if excluded_ids.include?(cv.custom_field_id)
      cf_values[cv.custom_field_id] = cv.value
    end
    new_issue.custom_field_values = cf_values if cf_values.any?

    if new_issue.save
      IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
      RedmineIssueRepeat::ChecklistCopy.copy_from(issue, new_issue)
      next_run = RedmineIssueRepeat::Scheduler.next_run_for(issue, base_time: Time.current)
      sched = RedmineIssueRepeat::IssueRepeatSchedule.find_or_initialize_by(issue_id: issue.id)
      sched.interval = interval if sched.new_record?
      sched.next_run_at = next_run if next_run
      sched.anchor_day = issue.created_on.day
      sched.save!
      Rails.logger.info("[IssueRepeat] repeat_now_issue: created new_issue=#{new_issue.id} from=#{issue.id} next_run_at=#{next_run}")
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = new_issue.errors.full_messages.join(', ')
      Rails.logger.error("[IssueRepeat] repeat_now_issue: failed to create copy for issue=#{issue.id}: #{new_issue.errors.full_messages.join(', ')}")
    end

    redirect_back fallback_location: home_path
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end