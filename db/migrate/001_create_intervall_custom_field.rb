class CreateIntervallCustomField < ActiveRecord::Migration[6.1]
  def up
    cf = IssueCustomField.find_by(name: 'Intervall')
    return if cf
    cf = IssueCustomField.new(
      name: 'Intervall',
      field_format: 'list',
      possible_values: ['täglich', 'wöchentlich', 'monatlich'],
      is_required: false
    )
    cf.visible = true
    cf.editable = true
    cf.trackers = Tracker.all
    cf.save
  end

  def down
    cf = IssueCustomField.find_by(name: 'Intervall')
    cf.destroy if cf
  end
end

