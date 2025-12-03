module RedmineIssueRepeat
  module Scheduler
    module_function

    def settings
      Setting.plugin_redmine_issue_repeat || {}
    end

    def parse_time(hhmm)
      return [9, 0] if hhmm.nil? || hhmm !~ /^\d{1,2}:\d{2}$/
      h, m = hhmm.split(':').map(&:to_i)
      [h % 24, m % 60]
    end

    def next_run_for(issue, base_time: Time.current)
      val = interval_value(issue)
      Rails.logger.info("[IssueRepeat] scheduler: issue=#{issue.id} interval=#{val.inspect} base_time=#{base_time}")
      return nil unless val
      case val
      when 'stündlich'
        minute = (settings['hourly_minute'] || '0').to_i % 60
        t = base_time + 3600
        run = Time.new(t.year, t.month, t.day, t.hour, minute, 0, t.utc_offset)
        Rails.logger.info("[IssueRepeat] scheduler: next_run=#{run}")
        run
      when 'täglich'
        h, m = parse_time(settings['daily_time'])
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

    def interval_value(issue)
      vals = CustomValue.where(customized_type: 'Issue', customized_id: issue.id).pluck(:value)
      v = vals.find { |x| x.present? }
      val = v && v.to_s.downcase
      case val
      when 'woechentlich' then 'wöchentlich'
      when 'taeglich' then 'täglich'
      when 'stundlich' then 'stündlich'
      else val
      end
    end

    def interval_cf_id(issue)
      CustomValue.where(customized_type: 'Issue', customized_id: issue.id).each do |cv|
        val = cv.value.to_s.downcase
        norm = case val
               when 'woechentlich' then 'wöchentlich'
               when 'taeglich' then 'täglich'
               when 'stundlich' then 'stündlich'
               else val
               end
        return cv.custom_field_id if %w[stündlich täglich wöchentlich monatlich].include?(norm)
      end
      nil
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
