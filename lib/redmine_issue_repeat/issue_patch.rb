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
          new_issue.subject = subject
          new_issue.description = description
          new_issue.assigned_to = assigned_to
          new_issue.estimated_hours = estimated_hours
          new_issue.start_date = compute_start_date(delta)
          new_issue.status = IssueStatus.default
          new_issue.custom_field_values = { cf.id => nil }
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
            anchor_minute = (Setting.plugin_redmine_issue_repeat['hourly_minute'] || '0').to_i
          when 'täglich'
            h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['daily_time'])
            anchor_hour, anchor_minute = h, m
          when 'wöchentlich'
            h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['weekly_time'])
            anchor_hour, anchor_minute = h, m
            anchor_day = created_on.to_date.cwday # Montag=1 ... Sonntag=7
          when 'monatlich'
            h, m = RedmineIssueRepeat::Scheduler.parse_time(Setting.plugin_redmine_issue_repeat['monthly_time'])
            anchor_hour, anchor_minute = h, m
            anchor_day = created_on.day
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
    end
  end
end
