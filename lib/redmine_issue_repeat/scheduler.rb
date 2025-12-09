module RedmineIssueRepeat
  module Scheduler
    module_function

    def settings
      Setting.plugin_redmine_issue_repeat || {}
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

    def cron_syntax_for_issue(issue)
      cf_cron = IssueCustomField.find_by(name: 'Intervall Cron Syntax')
      return nil unless cf_cron
      cv = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf_cron.id).limit(1).pluck(:value).first
      cv.presence
    end

    def parse_cron_field(cron_str)
      return nil unless cron_str
      parts = cron_str.strip.split(/\s+/)
      return nil unless parts.length == 5
      parts.map { |p| p.strip }
    end

    def matches_cron_field(value, field)
      return true if field == '*'
      return false if value.nil?
      
      # Einzelner Wert
      return value == field.to_i if field =~ /^\d+$/
      
      # Schritt: */5
      if field =~ /^\*\/(\d+)$/
        step = $1.to_i
        return value % step == 0
      end
      
      # Bereich: 1-5
      if field =~ /^(\d+)-(\d+)$/
        min, max = $1.to_i, $2.to_i
        return value >= min && value <= max
      end
      
      # Bereich mit Schritt: 1-10/2
      if field =~ /^(\d+)-(\d+)\/(\d+)$/
        min, max, step = $1.to_i, $2.to_i, $3.to_i
        return value >= min && value <= max && (value - min) % step == 0
      end
      
      # Liste: 1,3,5
      if field.include?(',')
        parts = field.split(',')
        parts.each do |part|
          return true if matches_cron_field(value, part.strip)
        end
        return false
      end
      
      false
    end

    def next_cron_time(cron_parts, base_time)
      minute_part, hour_part, day_part, month_part, weekday_part = cron_parts
      
      # Starte eine Minute nach base_time, um sicherzustellen, dass wir in der Zukunft sind
      current = base_time + 60
      max_iterations = 10000 # Verhindere Endlosschleifen
      iteration = 0
      
      loop do
        iteration += 1
        return nil if iteration > max_iterations
        
        # Prüfe Monat zuerst (größte Einheit)
        unless matches_cron_field(current.month, month_part)
          # Gehe zum ersten Tag des nächsten passenden Monats
          next_month = current.month + 1
          next_year = current.year
          if next_month > 12
            next_month = 1
            next_year += 1
          end
          # Finde den ersten passenden Monat
          while next_month <= 12 && !matches_cron_field(next_month, month_part)
            next_month += 1
            if next_month > 12
              next_month = 1
              next_year += 1
            end
          end
          current = Time.new(next_year, next_month, 1, 0, 0, 0, current.utc_offset)
          next
        end
        
        # Prüfe Tag des Monats
        unless matches_cron_field(current.day, day_part)
          current = Time.new(current.year, current.month, current.day + 1, 0, 0, 0, current.utc_offset)
          next
        end
        
        # Prüfe Wochentag
        # Cron: 0=Sonntag, 1=Montag, ..., 6=Samstag
        # Redmine cwday: 1=Montag, ..., 7=Sonntag
        # Konvertiere zu Cron-Format: Sonntag=0, Montag=1, etc.
        cron_weekday = current.cwday == 7 ? 0 : current.cwday
        unless matches_cron_field(cron_weekday, weekday_part)
          # Wenn Wochentag nicht passt, gehe zum nächsten Tag
          current = Time.new(current.year, current.month, current.day + 1, 0, 0, 0, current.utc_offset)
          next
        end
        
        # Prüfe Stunde
        unless matches_cron_field(current.hour, hour_part)
          current = Time.new(current.year, current.month, current.day, current.hour + 1, 0, 0, current.utc_offset)
          next
        end
        
        # Prüfe Minute
        unless matches_cron_field(current.min, minute_part)
          current = Time.new(current.year, current.month, current.day, current.hour, current.min + 1, 0, current.utc_offset)
          next
        end
        
        # Wenn wir hier ankommen, haben wir einen passenden Zeitpunkt gefunden
        return current if current > base_time
        
        # Sonst zur nächsten Minute gehen
        current = Time.new(current.year, current.month, current.day, current.hour, current.min + 1, 0, current.utc_offset)
      end
    end

    def next_run_for(issue, base_time: Time.current)
      val = interval_value(issue)
      Rails.logger.info("[IssueRepeat] scheduler: issue=#{issue.id} interval=#{val.inspect} base_time=#{base_time}")
      return nil unless val
      
      # Prüfe ob Custom-Intervall
      if val == 'custom'
        return parse_custom_interval(issue, base_time)
      end
      
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
        d = base_time.to_date + 7
        run = Time.new(d.year, d.month, d.day, h, m, 0, base_time.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      when 'monatlich'
        # Verwende pro-Ticket-Uhrzeit falls vorhanden, sonst Standard
        custom_time = custom_time_for_issue(issue)
        time_str = custom_time || settings['monthly_time']
        h, m = parse_time(time_str)
        anchor_day = issue.created_on.day
        next_date = next_month_date(base_time.to_date, anchor_day)
        run = Time.new(next_date.year, next_date.month, next_date.day, h, m, 0, base_time.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      else
        nil
      end
    end

    def parse_custom_interval(issue, base_time)
      # Zuerst prüfe ob Cron-Syntax vorhanden ist
      cron_str = cron_syntax_for_issue(issue)
      if cron_str && !cron_str.strip.empty?
        cron_parts = parse_cron_field(cron_str)
        if cron_parts
          next_time = next_cron_time(cron_parts, base_time)
          return next_time if next_time
        end
      end
      
      # Fallback auf alte Text-Syntax
      cf = IssueCustomField.find_by(name: 'Intervall')
      return nil unless cf
      cv = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf.id).limit(1).pluck(:value).first
      return nil unless cv
      custom_value = cv.to_s.strip
      
      # Entferne "custom" Präfix falls vorhanden
      custom_value = custom_value.sub(/^custom\s*:?\s*/i, '').strip
      
      # Falls nach Entfernen des Präfixes nichts übrig bleibt, verwende den ursprünglichen Wert
      custom_value = cv.to_s.strip if custom_value.empty?
      
      # Parse verschiedene Formate
      # "jährlich" oder "1 Jahr"
      if custom_value =~ /(?:jährlich|1\s*jahr|year)/i
        anchor_day = issue.created_on.day
        anchor_month = issue.created_on.month
        next_date = base_time.to_date
        # Finde nächstes Jahr mit gleichem Tag/Monat
        loop do
          next_date = next_date.next_year
          last_day = Date.civil(next_date.year, anchor_month, -1).day
          day = [anchor_day, last_day].min
          next_date = Date.civil(next_date.year, anchor_month, day)
          break if next_date > base_time.to_date
        end
        h, m = parse_time(settings['monthly_time'])
        return Time.new(next_date.year, next_date.month, next_date.day, h, m, 0, base_time.utc_offset)
      end
      
      # "alle X Monate" oder "X Monate"
      if custom_value =~ /(?:alle\s*)?(\d+)\s*monat/i
        months = $1.to_i
        anchor_day = issue.created_on.day
        next_date = base_time.to_date
        # Finde nächsten Monat
        loop do
          next_date = next_date >> months
          last_day = Date.civil(next_date.year, next_date.month, -1).day
          day = [anchor_day, last_day].min
          next_date = Date.civil(next_date.year, next_date.month, day)
          break if next_date > base_time.to_date
        end
        h, m = parse_time(settings['monthly_time'])
        return Time.new(next_date.year, next_date.month, next_date.day, h, m, 0, base_time.utc_offset)
      end
      
      # "alle X Wochen" oder "X Wochen"
      if custom_value =~ /(?:alle\s*)?(\d+)\s*woche/i
        weeks = $1.to_i
        h, m = parse_time(settings['weekly_time'])
        d = base_time.to_date + (weeks * 7)
        return Time.new(d.year, d.month, d.day, h, m, 0, base_time.utc_offset)
      end
      
      # "alle X Tage" oder "X Tage"
      if custom_value =~ /(?:alle\s*)?(\d+)\s*tag/i
        days = $1.to_i
        custom_time = custom_time_for_issue(issue)
        time_str = custom_time || settings['daily_time']
        h, m = parse_time(time_str)
        d = base_time.to_date + days
        return Time.new(d.year, d.month, d.day, h, m, 0, base_time.utc_offset)
      end
      
      nil
    end

    def interval_value(issue)
      cf = IssueCustomField.find_by(name: 'Intervall')
      return nil unless cf
      v = CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: cf.id).limit(1).pluck(:value).first
      return nil unless v
      val = v.to_s.strip
      val_lower = val.downcase
      
      # Prüfe ob es ein Custom-Intervall ist (beginnt mit "custom" oder enthält Custom-Syntax)
      if val_lower.start_with?('custom') || val_lower =~ /(?:jährlich|alle\s+\d+|monat|woche|tag)/i
        return 'custom'
      end
      
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
