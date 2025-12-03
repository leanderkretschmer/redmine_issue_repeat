class ExtendIssueRepeatSchedules < ActiveRecord::Migration[6.1]
  def change
    add_column :issue_repeat_schedules, :times_run, :integer, default: 0, null: false
    add_column :issue_repeat_schedules, :active, :boolean, default: true, null: false
    add_column :issue_repeat_schedules, :anchor_hour, :integer
    add_column :issue_repeat_schedules, :anchor_minute, :integer
    add_column :issue_repeat_schedules, :backup_anchor_day, :integer
  end
end

