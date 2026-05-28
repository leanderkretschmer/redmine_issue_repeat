require 'redmine'

require_relative 'lib/redmine_issue_repeat'

Redmine::Plugin.register :redmine_issue_repeat do
  name 'Redmine Issue Repeat'
  author 'Leander Kretschmer'
  author_url 'https://github.com/leanderkretschmer/redmine_issue_repeat'
  description 'Erstellt automatisch eine Kopie eines Tickets basierend auf dem Intervall.'
  version '0.2.0'
  settings default: {
    'daily_time' => '09:00',
    'weekly_time' => '09:00',
    'monthly_time' => '09:00',
    'hourly_minute' => '0',
    'copy_issue_bg_color' => '#fffbe6',
    'add_prefix_to_copied_issues' => false,
    'copied_issue_prefix' => '➚'
  }, partial: 'settings/redmine_issue_repeat'
end
