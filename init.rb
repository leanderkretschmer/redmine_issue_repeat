require 'redmine'

require_relative 'lib/redmine_issue_repeat'

Redmine::Plugin.register :redmine_issue_repeat do
  name 'Redmine Issue Repeat'
  author 'Leander Kretschmer'
  author_url 'https://github.com/leanderkretschmer/redmine_issue_repeat'
  description 'Erstellt automatisch eine Kopie eines Tickets basierend auf dem Intervall.'
  version '0.1.0'
end

