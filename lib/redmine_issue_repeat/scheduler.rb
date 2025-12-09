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
        minute = (settings['hourly_minute'] || '0').to_i % 60
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
        h, m = parse_time(settings['weekly_time'])
        d = base_time.to_date + 7
        run = Time.new(d.year, d.month, d.day, h, m, 0, base_time.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      when 'monatlich'
        h, m = parse_time(settings['monthly_time'])
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
