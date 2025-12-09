module RedmineIssueRepeat
  class ViewHooks < Redmine::Hook::ViewListener
    render_on :view_issues_show_details_bottom, partial: 'redmine_issue_repeat/highlight_copy_issue'
    render_on :view_issues_form_details_bottom, partial: 'redmine_issue_repeat/intervall_time_field'
  end
end

