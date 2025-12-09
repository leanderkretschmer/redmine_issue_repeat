module RedmineIssueRepeat
  module Scheduler
    module_function

    def settings
      Setting.plugin_redmine_issue_repeat || {}
    end

    def add_prefix_to_subject(subject)
      return subject if subject.nil?
      
      plugin_settings = settings
      add_prefix = plugin_settings['add_prefix_to_copied_issues'] == '1' || plugin_settings['add_prefix_to_copied_issues'] == true
      return subject unless add_prefix
      
      prefix = plugin_settings['copied_issue_prefix'].to_s.strip
      prefix = '➚' if prefix.empty?
      
      # Füge Prefix nur hinzu, wenn es noch nicht vorhanden ist
      return subject if subject.start_with?("#{prefix} ")
      
      "#{prefix} #{subject}"
    end

    def parse_time(hhmm)
      return [9, 0] if hhmm.nil? || hhmm.to_s.strip.empty?
      # Validiere Format: HH:MM mit Stunden 0-23 und Minuten 0-59
      return [9, 0] unless hhmm.to_s.strip =~ /^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/
      h, m = hhmm.split(':').map(&:to_i)
      # Stelle sicher, dass Stunden und Minuten im gültigen Bereich sind
      h = [[h, 0].max, 23].min
      m = [[m, 0].max, 59].min
      [h, m]
    end

    def custom_time_for_issue(issue)
      cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
      return nil unless cf_time
      cv = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf_time.id).limit(1).pluck(:value).first
      cv.presence
    end

    def weekday_for_issue(issue)
      cf_weekday = IssueCustomField.find_by(name: 'Intervall Wochentag')
      return nil unless cf_weekday
      cv = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf_weekday.id).limit(1).pluck(:value).first
      cv.presence
    end

    def monthday_option_for_issue(issue)
      cf_monthday = IssueCustomField.find_by(name: 'Intervall Monatstag')
      return nil unless cf_monthday
      cv = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf_monthday.id).limit(1).pluck(:value).first
      cv.presence
    end

    def weekday_name_to_number(weekday_name)
      mapping = {
        'Montag' => 1,
        'Dienstag' => 2,
        'Mittwoch' => 3,
        'Donnerstag' => 4,
        'Freitag' => 5,
        'Samstag' => 6,
        'Sonntag' => 7
      }
      mapping[weekday_name] || nil
    end

    def calculate_month_day(option, issue_created_day, target_date)
      case option
      when 'Anfang des Monats (1.)'
        1
      when 'Ende des Monats (29-31)'
        # Letzter Tag des Monats
        Date.civil(target_date.year, target_date.month, -1).day
      when 'Mitte des Monats'
        # 15. des Monats
        15
      when 'Aktuelles Datum'
        # Tag des ursprünglichen Tickets, aber angepasst an Monatslänge
        last_day = Date.civil(target_date.year, target_date.month, -1).day
        [issue_created_day, last_day].min
      else
        # Fallback: Aktuelles Datum
        last_day = Date.civil(target_date.year, target_date.month, -1).day
        [issue_created_day, last_day].min
      end
    end

    def next_run_for(issue, base_time: Time.current)
      val = interval_value(issue)
      Rails.logger.info("[IssueRepeat] scheduler: issue=#{issue.id} interval=#{val.inspect} base_time=#{base_time}")
      return nil unless val
      
      case val
      when 'stündlich'
        # Verwende pro-Ticket-Uhrzeit falls vorhanden (nur Minute wird verwendet)
        custom_time = custom_time_for_issue(issue)
        if custom_time
          _, m = parse_time(custom_time)
          minute = m % 60
        else
          minute = (settings['hourly_minute'] || '0').to_i % 60
        end
        t = base_time + 3600
        run = Time.new(t.year, t.month, t.day, t.hour, minute, 0, t.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      when 'täglich'
        # Verwende pro-Ticket-Uhrzeit falls vorhanden, sonst Standard
        custom_time = custom_time_for_issue(issue)
        time_str = custom_time || settings['daily_time']
        h, m = parse_time(time_str)
        d = base_time.to_date + 1
        run = Time.new(d.year, d.month, d.day, h, m, 0, base_time.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      when 'wöchentlich'
        # Verwende pro-Ticket-Uhrzeit falls vorhanden, sonst Standard
        custom_time = custom_time_for_issue(issue)
        time_str = custom_time || settings['weekly_time']
        h, m = parse_time(time_str)
        
        # Prüfe ob ein Wochentag ausgewählt wurde
        weekday_name = weekday_for_issue(issue)
        if weekday_name
          target_weekday = weekday_name_to_number(weekday_name)
          if target_weekday
            # Finde nächsten passenden Wochentag
            current_weekday = base_time.to_date.cwday
            days_ahead = target_weekday - current_weekday
            days_ahead += 7 if days_ahead <= 0 # Wenn der Tag bereits vorbei ist, nächste Woche
            d = base_time.to_date + days_ahead
          else
            d = base_time.to_date + 7
          end
        else
          # Fallback: +7 Tage wie bisher
          d = base_time.to_date + 7
        end
        
        run = Time.new(d.year, d.month, d.day, h, m, 0, base_time.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      when 'monatlich'
        # Verwende pro-Ticket-Uhrzeit falls vorhanden, sonst Standard
        custom_time = custom_time_for_issue(issue)
        time_str = custom_time || settings['monthly_time']
        h, m = parse_time(time_str)
        
        # Berechne nächsten Monat
        next_month_date = base_time.to_date.next_month
        
        # Prüfe Monatstag-Option
        monthday_option = monthday_option_for_issue(issue)
        if monthday_option
          anchor_day = calculate_month_day(monthday_option, issue.created_on.day, next_month_date)
        else
          # Fallback: Aktuelles Datum
          anchor_day = calculate_month_day('Aktuelles Datum', issue.created_on.day, next_month_date)
        end
        
        # Stelle sicher, dass der Tag im Monat existiert
        last_day = Date.civil(next_month_date.year, next_month_date.month, -1).day
        anchor_day = [anchor_day, last_day].min
        
        run = Time.new(next_month_date.year, next_month_date.month, anchor_day, h, m, 0, base_time.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      else
        nil
      end
    end


    def interval_value(issue)
      cf = IssueCustomField.find_by(name: 'Intervall')
      return nil unless cf
      v = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf.id).limit(1).pluck(:value).first
      return nil unless v
      val = v.to_s.strip
      val_lower = val.downcase
      
      case val_lower
      when 'woechentlich' then 'wöchentlich'
      when 'taeglich' then 'täglich'
      when 'stundlich' then 'stündlich'
      when 'stündlich', 'täglich', 'wöchentlich', 'monatlich' then val_lower
      else nil
      end
    end

    def interval_cf_id(issue)
      cf = IssueCustomField.find_by(name: 'Intervall')
      cf&.id
    end

    def next_month_date(from_date, anchor_day)
      nm = from_date.next_month
      last = Date.civil(nm.year, nm.month, -1)
      day = [anchor_day, last.day].min
      Date.civil(nm.year, nm.month, day)
    end

    def start_date_for(interval, from_time)
      case interval
      when 'stündlich'
        from_time.to_date
      when 'täglich'
        (from_time.to_date)
      when 'wöchentlich'
        (from_time.to_date)
      when 'monatlich'
        (from_time.to_date)
      else
        from_time.to_date
      end
    end
  end
end
