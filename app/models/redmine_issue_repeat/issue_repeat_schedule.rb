class RedmineIssueRepeat::IssueRepeatSchedule < ActiveRecord::Base
  self.table_name = 'issue_repeat_schedules'

  belongs_to :issue

  validates :issue_id, presence: true
  validates :interval, inclusion: { in: %w[stündlich täglich wöchentlich monatlich] }
  validates :next_run_at, presence: true
  validates :times_run, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :active, inclusion: { in: [true, false] }
end
