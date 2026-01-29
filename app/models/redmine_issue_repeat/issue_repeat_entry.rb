class RedmineIssueRepeat::IssueRepeatEntry < ActiveRecord::Base
  self.table_name = 'issue_repeat_entries'
  belongs_to :issue, foreign_key: :ticket_id, optional: true
  validates :ticket_id, presence: true
  validates :intervall, inclusion: { in: %w[stündlich täglich wöchentlich monatlich] }
end
