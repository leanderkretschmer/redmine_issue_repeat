class AddCronSyntaxField < ActiveRecord::Migration[6.1]
  def up
    # Erstelle Custom Field für Cron-Syntax
    cf_cron = IssueCustomField.find_by(name: 'Intervall Cron Syntax')
    if cf_cron
      # Feld existiert bereits, aktualisiere es falls nötig
      cf_cron.field_format = 'string'
      cf_cron.is_required = false
      cf_cron.visible = true
      cf_cron.editable = true
      cf_cron.default_value = ''
      cf_cron.trackers = Tracker.all unless cf_cron.trackers.any?
      cf_cron.save
    else
      # Feld existiert nicht, erstelle es neu
      cf_cron = IssueCustomField.new(
        name: 'Intervall Cron Syntax',
        field_format: 'string',
        is_required: false,
        visible: true,
        editable: true,
        default_value: ''
      )
      cf_cron.trackers = Tracker.all
      cf_cron.save
    end
  end

  def down
    cf_cron = IssueCustomField.find_by(name: 'Intervall Cron Syntax')
    cf_cron.destroy if cf_cron
  end
end

