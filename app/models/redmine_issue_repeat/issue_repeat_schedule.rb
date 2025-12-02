class RedmineIssueRepeat::IssueRepeatSchedule < ActiveRecord::Base
  self.table_name = 'issue_repeat_schedules'

  belongs_to :issue

  validates :issue_id, presence: true
  validates :interval, inclusion: { in: %w[stündlich täglich wöchentlich monatlich] }
  validates :next_run_at, presence: true
end

