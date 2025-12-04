RedmineApp::Application.routes.draw do
  post 'redmine_issue_repeat/repeat_now/:id', to: 'redmine_issue_repeat/actions#repeat_now', as: 'redmine_issue_repeat_repeat_now_issue'
end

