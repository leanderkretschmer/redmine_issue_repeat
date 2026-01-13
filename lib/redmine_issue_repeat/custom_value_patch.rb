module RedmineIssueRepeat
  module CustomValuePatch
    def self.apply
      Issue.class_eval do
        # Überschreibe custom_field_values= um Wochentage zu sortieren
        alias_method :original_custom_field_values=, :custom_field_values= unless method_defined?(:original_custom_field_values=)
        
        def custom_field_values=(values)
          # Prüfe ob Wochentag-Werte gesetzt werden
          weekday_cf = IssueCustomField.find_by(name: 'Intervall Wochentag')
          
          if weekday_cf && values.is_a?(Hash)
            weekday_cf_id = weekday_cf.id
            
            # Definiere die richtige Reihenfolge
            weekday_order = {
              'Montag' => 1,
              'Dienstag' => 2,
              'Mittwoch' => 3,
              'Donnerstag' => 4,
              'Freitag' => 5,
              'Samstag' => 6,
              'Sonntag' => 7
            }
            
            # Wenn Wochentag-Werte gesetzt werden, sortiere sie
            if values[weekday_cf_id].is_a?(Array) && values[weekday_cf_id].length > 1
              values[weekday_cf_id] = values[weekday_cf_id].sort_by { |v| weekday_order[v.to_s] || 999 }
            end
          end
          
          # Rufe die ursprüngliche Methode auf
          original_custom_field_values=(values)
        end
      end
    end
  end
end
