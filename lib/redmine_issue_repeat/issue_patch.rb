module RedmineIssueRepeat
  module IssuePatch
    def self.apply
      Issue.include InstanceMethods unless Issue < InstanceMethods
      Issue.class_eval do
        after_commit :repeat_issue_after_create, on: :create
      end
    end

    module InstanceMethods
      def repeat_issue_after_create
        cf = IssueCustomField.find_by(name: 'Intervall')
        return unless cf

        val = CustomValue.where(customized_type: 'Issue', customized_id: id, custom_field_id: cf.id).limit(1).pluck(:value).first
        return if val.nil? || val.to_s.strip.empty?
        interval = val.to_s.downcase

        delta = case interval
                when 'täglich' then 1
                when 'woechentlich', 'wöchentlich' then 7
                when 'monatlich' then :month
                else nil
                end

        if delta && interval != 'stündlich'
          new_issue = Issue.new
          new_issue.project = project
          new_issue.tracker = tracker
          new_issue.subject = RedmineIssueRepeat::Scheduler.add_prefix_to_subject(subject)
          new_issue.description = description
          new_issue.assigned_to = assigned_to
          new_issue.author = author
          new_issue.priority = priority
          new_issue.category = category
          new_issue.fixed_version = fixed_version
          new_issue.due_date = due_date
          new_issue.estimated_hours = estimated_hours
          new_issue.start_date = compute_start_date(delta)
          if new_issue.due_date && new_issue.start_date && new_issue.start_date > new_issue.due_date
            new_issue.due_date = new_issue.start_date
          end
          new_issue.status = default_issue_status
          # Copy custom fields except all Intervall-related fields
          cf_values = {}
          excluded_ids = RedmineIssueRepeat::Scheduler.interval_related_cf_ids
          custom_field_values.each do |cv|
            next if excluded_ids.include?(cv.custom_field_id)
            cf_values[cv.custom_field_id] = cv.value
          end
          new_issue.custom_field_values = cf_values if cf_values.any?
          if new_issue.save
            IssueRelation.create(issue_from: new_issue, issue_to: self, relation_type: 'relates')
          end
        end

        iv = RedmineIssueRepeat::Scheduler.interval_value(self)
        next_run = RedmineIssueRepeat::Scheduler.next_run_for(self, base_time: Time.current)
        if iv && next_run
          anchor_hour = nil
          anchor_minute = nil
          anchor_day = nil
          backup_anchor_day = nil

          case iv
          when 'stündlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden (nur Minute wird verwendet)
            cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
            if cf_time
              cv = CustomValue.where(customized_type: 'Issue', customized_id: id, custom_field_id: cf_time.id).limit(1).pluck(:value).first
              if cv.presence
                _, m = RedmineIssueRepeat::Scheduler.parse_time(cv)
                anchor_minute = m
              else
                anchor_minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
              end
            else
              anchor_minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
            end
          when 'täglich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
            custom_time = nil
            if cf_time
              cv = CustomValue.where(customized_type: 'Issue', customized_id: id, custom_field_id: cf_time.id).limit(1).pluck(:value).first
              custom_time = cv.presence
            end
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['daily_time']
            h, m = RedmineIssueRepeat::Scheduler.parse_time(time_str)
            anchor_hour, anchor_minute = h, m
          when 'wöchentlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
            custom_time = nil
            if cf_time
              cv = CustomValue.where(customized_type: 'Issue', customized_id: id, custom_field_id: cf_time.id).limit(1).pluck(:value).first
              custom_time = cv.presence
            end
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['weekly_time']
            h, m = RedmineIssueRepeat::Scheduler.parse_time(time_str)
            anchor_hour, anchor_minute = h, m
            # Verwende ausgewählten Wochentag falls vorhanden, sonst Tag der Erstellung
            weekday_name = RedmineIssueRepeat::Scheduler.weekday_for_issue(self)
            if weekday_name
              anchor_day = RedmineIssueRepeat::Scheduler.weekday_name_to_number(weekday_name)
            else
              anchor_day = created_on.to_date.cwday # Montag=1 ... Sonntag=7
            end
          when 'monatlich'
            # Verwende pro-Ticket-Uhrzeit falls vorhanden
            cf_time = IssueCustomField.find_by(name: 'Intervall Uhrzeit')
            custom_time = nil
            if cf_time
              cv = CustomValue.where(customized_type: 'Issue', customized_id: id, custom_field_id: cf_time.id).limit(1).pluck(:value).first
              custom_time = cv.presence
            end
            time_str = custom_time || Setting.plugin_redmine_issue_repeat['monthly_time']
            h, m = RedmineIssueRepeat::Scheduler.parse_time(time_str)
            anchor_hour, anchor_minute = h, m
            # Verwende Monatstag-Option falls vorhanden
            monthday_option = RedmineIssueRepeat::Scheduler.monthday_option_for_issue(self)
            if monthday_option
              # Berechne Tag basierend auf Option (für ersten Monat)
              next_month_date = created_on.to_date.next_month
              anchor_day = RedmineIssueRepeat::Scheduler.calculate_month_day(monthday_option, created_on.day, next_month_date)
            else
              anchor_day = created_on.day
            end
            backup_anchor_day = if anchor_day == 31
                                  30
                                elsif anchor_day == 30
                                  29
                                else
                                  nil
                                end
          end

          RedmineIssueRepeat::IssueRepeatSchedule.create!(
            issue_id: id,
            interval: iv,
            next_run_at: next_run,
            anchor_day: anchor_day,
            anchor_hour: anchor_hour,
            anchor_minute: anchor_minute,
            backup_anchor_day: backup_anchor_day,
            active: true,
            times_run: 0
          )
        end
      end

      def compute_start_date(delta)
        d = Date.today
        if delta == :month
          anchor = created_on.day
          next_date = RedmineIssueRepeat::Scheduler.next_month_date(d, anchor)
          next_date
        else
          d + delta
        end
      end

      def default_issue_status
        IssueStatus.where(is_closed: false).order(:id).first || IssueStatus.order(:id).first
      end
    end
  end
end
