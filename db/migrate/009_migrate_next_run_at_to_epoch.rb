class MigrateNextRunAtToEpoch < ActiveRecord::Migration[6.1]
  class IssueRepeatSchedule < ActiveRecord::Base
    self.table_name = 'issue_repeat_schedules'
  end

  def up
    add_column :issue_repeat_schedules, :next_run_at_epoch, :bigint
    IssueRepeatSchedule.reset_column_information
    IssueRepeatSchedule.find_each do |s|
      val = s.read_attribute(:next_run_at)
      s.update_columns(next_run_at_epoch: val.to_i) if val
    end
    remove_index :issue_repeat_schedules, :next_run_at if index_exists?(:issue_repeat_schedules, :next_run_at)
    remove_column :issue_repeat_schedules, :next_run_at, :datetime
    rename_column :issue_repeat_schedules, :next_run_at_epoch, :next_run_at
    add_index :issue_repeat_schedules, :next_run_at
  end

  def down
    add_column :issue_repeat_schedules, :next_run_at_dt, :datetime
    IssueRepeatSchedule.reset_column_information
    IssueRepeatSchedule.find_each do |s|
      val = s.read_attribute(:next_run_at)
      s.update_columns(next_run_at_dt: Time.at(val)) if val
    end
    remove_index :issue_repeat_schedules, :next_run_at if index_exists?(:issue_repeat_schedules, :next_run_at)
    remove_column :issue_repeat_schedules, :next_run_at, :bigint
    rename_column :issue_repeat_schedules, :next_run_at_dt, :next_run_at
    add_index :issue_repeat_schedules, :next_run_at
  end
end
