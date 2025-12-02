class CreateIssueRepeatSchedules < ActiveRecord::Migration[6.1]
  def change
    create_table :issue_repeat_schedules do |t|
      t.integer :issue_id, null: false
      t.string :interval, null: false
      t.datetime :next_run_at, null: false
      t.integer :anchor_day
      t.timestamps
    end
    add_index :issue_repeat_schedules, [:issue_id]
    add_index :issue_repeat_schedules, [:next_run_at]
  end
end

