class AddDateInSubjectField < ActiveRecord::Migration[6.1]
  def up
    cf = IssueCustomField.find_by(name: 'Intervall Datum im Titel')
    return if cf
    cf = IssueCustomField.new(
      name: 'Intervall Datum im Titel',
      field_format: 'bool',
      is_required: false,
      visible: true,
      editable: true,
      default_value: '0',
      description: 'Hängt das Datum der jeweiligen Kopie an die Ticketbezeichnung an (z.B. "JourFixe Gruppe 23.10.2026").'
    )
    cf.trackers = Tracker.all
    cf.save
    Rails.logger.info("[IssueRepeat] Created Custom Field 'Intervall Datum im Titel'")
  end

  def down
    cf = IssueCustomField.find_by(name: 'Intervall Datum im Titel')
    cf.destroy if cf
  end
end
