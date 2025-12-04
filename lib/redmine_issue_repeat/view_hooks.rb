module RedmineIssueRepeat
  class ViewHooks < Redmine::Hook::ViewListener
    render_on :view_issues_show_details_bottom, partial: 'redmine_issue_repeat/highlight_copy_issue'
  end
end

