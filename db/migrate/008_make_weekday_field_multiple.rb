class MakeWeekdayFieldMultiple < ActiveRecord::Migration[6.1]
  def up
    # Aktualisiere Wochentag-Feld auf Multi-Select
    cf_weekday = IssueCustomField.find_by(name: 'Intervall Wochentag')
    if cf_weekday
      # Setze multiple auf true für Multi-Select
      cf_weekday.multiple = true
      cf_weekday.save
      Rails.logger.info("[IssueRepeat] Updated 'Intervall Wochentag' field to support multiple selection")
    end
  end

  def down
    # Setze multiple zurück auf false
    cf_weekday = IssueCustomField.find_by(name: 'Intervall Wochentag')
    if cf_weekday
      cf_weekday.multiple = false
      cf_weekday.save
      Rails.logger.info("[IssueRepeat] Reverted 'Intervall Wochentag' field to single selection")
    end
  end
end
