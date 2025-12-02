class AddHourlyToIntervallField < ActiveRecord::Migration[6.1]
  def up
    cf = IssueCustomField.find_by(name: 'Intervall')
    return unless cf
    vals = cf.possible_values || []
    unless vals.include?('stündlich')
      cf.possible_values = vals + ['stündlich']
      cf.save
    end
  end

  def down
    cf = IssueCustomField.find_by(name: 'Intervall')
    return unless cf
    cf.possible_values = (cf.possible_values || []).reject { |v| v == 'stündlich' }
    cf.save
  end
end

