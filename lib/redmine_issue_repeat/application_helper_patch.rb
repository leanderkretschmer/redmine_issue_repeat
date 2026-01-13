module RedmineIssueRepeat
  module ApplicationHelperPatch
    def self.apply
      ApplicationHelper.class_eval do
        # Überschreibe show_value um Wochentage zu sortieren
        alias_method :original_show_value, :show_value unless method_defined?(:original_show_value)
        
        def show_value(custom_value, html = false)
          result = original_show_value(custom_value, html)
          
          # Prüfe ob dies ein Wochentag-Feld ist
          cf = custom_value.custom_field
          return result unless cf && cf.name == 'Intervall Wochentag' && cf.multiple?
          
          # Für Multi-Select-Felder müssen wir die Werte sortieren
          issue = custom_value.customized
          return result unless issue.is_a?(Issue)
          
          # Hole alle Werte für dieses Issue und dieses Feld
          all_values = CustomValue.where(
            customized_type: 'Issue',
            customized_id: issue.id,
            custom_field_id: cf.id
          ).pluck(:value).compact
          
          return result if all_values.empty? || all_values.length <= 1
          
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
          
          # Sortiere die Werte nach der definierten Reihenfolge
          sorted_values = all_values.sort_by { |v| weekday_order[v] || 999 }
          
          # Erstelle den sortierten Text
          if html
            sorted_values.map { |v| h(v) }.join(', ').html_safe
          else
            sorted_values.join(', ')
          end
        end
      end
    end
  end
end
