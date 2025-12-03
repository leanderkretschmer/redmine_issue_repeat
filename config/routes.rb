RedmineApp::Application.routes.draw do
  post 'redmine_issue_repeat/repeat_now/:id', to: 'redmine_issue_repeat/repeats#repeat_now', as: 'redmine_issue_repeat_repeat_now'
  post 'redmine_issue_repeat/repeat_now_issue/:id', to: 'redmine_issue_repeat/repeats#repeat_now_issue', as: 'redmine_issue_repeat_repeat_now_issue'
end