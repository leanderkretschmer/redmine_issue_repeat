class RedmineIssueRepeat::RepeatsController < ApplicationController
  before_action :require_admin

  def repeat_now
    sched = RedmineIssueRepeat::IssueRepeatSchedule.find(params[:id])
    issue = sched.issue
    interval = RedmineIssueRepeat::Scheduler.interval_value(issue)
    return render_404 unless issue && interval

    new_issue = Issue.new
    new_issue.project = issue.project
    new_issue.tracker = issue.tracker
    new_issue.subject = issue.subject
    new_issue.description = issue.description
    new_issue.assigned_to = issue.assigned_to
    new_issue.estimated_hours = issue.estimated_hours
    new_issue.start_date = RedmineIssueRepeat::Scheduler.start_date_for(interval, Time.current)
    new_issue.status = IssueStatus.default

    cf = IssueCustomField.find_by(name: 'Intervall')
    new_issue.custom_field_values = { cf.id => nil } if cf

    if new_issue.save
      IssueRelation.create(issue_from: new_issue, issue_to: issue, relation_type: 'relates')
      next_run = RedmineIssueRepeat::Scheduler.next_run_for(issue, base_time: Time.current)
      sched.update!(next_run_at: next_run) if next_run
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = new_issue.errors.full_messages.join(', ')
    end

    redirect_back fallback_location: home_path
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end