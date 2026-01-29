class CreateIssueRepeatEntries < ActiveRecord::Migration[6.1]
  def change
    create_table :issue_repeat_entries do |t|
      t.integer :ticket_id, null: false
      t.string :ticket_title
      t.string :intervall, null: false
      t.integer :intervall_hour
      t.text :intervall_weekday
      t.integer :intervall_monthday
      t.boolean :intervall_state, default: true, null: false
      t.bigint :last_changed
      t.bigint :last_run
      t.integer :times_run, default: 0, null: false
      t.bigint :next_run
      t.timestamps
    end
    add_index :issue_repeat_entries, [:ticket_id]
    add_index :issue_repeat_entries, [:next_run]
    add_index :issue_repeat_entries, [:intervall_state]
  end
end
