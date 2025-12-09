class AddCustomTimeFieldAndSortIntervall < ActiveRecord::Migration[6.1]
  def up
    # Erstelle oder aktualisiere Custom Field für pro-Ticket-Uhrzeit
    cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
    if cf_time
      # Feld existiert bereits, aktualisiere es falls nötig
      cf_time.field_format = 'string'
      cf_time.is_required = false
      cf_time.visible = true
      cf_time.editable = true
      cf_time.default_value = '' if cf_time.default_value.nil?
      cf_time.regexp = '^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$'
      cf_time.trackers = Tracker.all unless cf_time.trackers.any?
      cf_time.save
    else
      # Feld existiert nicht, erstelle es neu
      cf_time = IssueCustomField.new(
        name: 'Intervall Uhrzeit',
        field_format: 'string',
        is_required: false,
        visible: true,
        editable: true,
        default_value: '',
        regexp: '^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$'
      )
      cf_time.trackers = Tracker.all
      cf_time.save
    end

    # Aktualisiere Intervall-Feld mit korrekter Sortierung und Custom-Option
    cf = IssueCustomField.find_by(name: 'Intervall')
    if cf
      # Sortierung: stündlich, täglich, wöchentlich, monatlich, custom
      # Hinweis: Für Custom-Intervalle kann der Benutzer die Syntax direkt eingeben
      # z.B. "custom: jährlich" oder "custom: alle 3 Monate"
      expected_values = ['stündlich', 'täglich', 'wöchentlich', 'monatlich', 'custom']
      if cf.possible_values != expected_values
        cf.possible_values = expected_values
        cf.save
      end
    end
  end

  def down
    cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
    cf_time.destroy if cf_time

    cf = IssueCustomField.find_by(name: 'Intervall')
    if cf
      # Zurück zur alten Sortierung ohne custom
      cf.possible_values = ['stündlich', 'täglich', 'wöchentlich', 'monatlich']
      cf.save
    end
  end
end

