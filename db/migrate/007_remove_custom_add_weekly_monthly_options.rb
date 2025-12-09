class RemoveCustomAddWeeklyMonthlyOptions < ActiveRecord::Migration[6.1]
  def up
    # Entferne Custom-Option aus Intervall-Feld
    cf = IssueCustomField.find_by(name: 'Intervall')
    if cf
      # Entferne 'custom' aus possible_values
      current_values = cf.possible_values || []
      new_values = current_values.reject { |v| v == 'custom' }
      if new_values != current_values
        cf.possible_values = new_values
        cf.save
      end
    end

    # Verstecke Cron-Syntax-Feld (löschen wäre zu destruktiv)
    cf_cron = IssueCustomField.find_by(name: 'Intervall Cron Syntax')
    if cf_cron
      cf_cron.visible = false
      cf_cron.editable = false
      cf_cron.save
    end

    # Erstelle Wochentag-Feld für wöchentlich
    cf_weekday = IssueCustomField.find_by(name: 'Intervall Wochentag')
    unless cf_weekday
      cf_weekday = IssueCustomField.new(
        name: 'Intervall Wochentag',
        field_format: 'list',
        possible_values: ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
        is_required: false,
        visible: true,
        editable: true,
        default_value: ''
      )
      cf_weekday.trackers = Tracker.all
      cf_weekday.save
    end

    # Erstelle Monatstag-Option-Feld für monatlich
    cf_monthday = IssueCustomField.find_by(name: 'Intervall Monatstag')
    unless cf_monthday
      cf_monthday = IssueCustomField.new(
        name: 'Intervall Monatstag',
        field_format: 'list',
        possible_values: ['Anfang des Monats (1.)', 'Ende des Monats (29-31)', 'Mitte des Monats', 'Aktuelles Datum'],
        is_required: false,
        visible: true,
        editable: true,
        default_value: ''
      )
      cf_monthday.trackers = Tracker.all
      cf_monthday.save
    end
  end

  def down
    # Füge Custom-Option wieder hinzu
    cf = IssueCustomField.find_by(name: 'Intervall')
    if cf
      current_values = cf.possible_values || []
      unless current_values.include?('custom')
        cf.possible_values = current_values + ['custom']
        cf.save
      end
    end

    # Zeige Cron-Syntax-Feld wieder
    cf_cron = IssueCustomField.find_by(name: 'Intervall Cron Syntax')
    if cf_cron
      cf_cron.visible = true
      cf_cron.editable = true
      cf_cron.save
    end

    # Lösche neue Felder
    cf_weekday = IssueCustomField.find_by(name: 'Intervall Wochentag')
    cf_weekday.destroy if cf_weekday

    cf_monthday = IssueCustomField.find_by(name: 'Intervall Monatstag')
    cf_monthday.destroy if cf_monthday
  end
end

