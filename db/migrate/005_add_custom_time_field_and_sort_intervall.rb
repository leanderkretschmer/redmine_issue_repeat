class AddCustomTimeFieldAndSortIntervall < ActiveRecord::Migration[6.1]
  def up
    # Erstelle Custom Field für pro-Ticket-Uhrzeit
    cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
    unless cf_time
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
      cf.possible_values = ['stündlich', 'täglich', 'wöchentlich', 'monatlich', 'custom']
      # Erlaube auch freie Texteingabe für Custom-Syntax
      # In Redmine können List-Felder nur vordefinierte Werte haben,
      # daher wird die Syntax als Teil des "custom" Wertes gespeichert
      cf.save
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

