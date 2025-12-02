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
        val = custom_field_value(cf.id)
        return if val.nil? || val.to_s.strip.empty?
        interval = val.to_s.downcase
        delta = case interval
                when 'täglich' then 1
                when 'woechentlich', 'wöchentlich' then 7
                when 'monatlich' then :month
                else nil
                end
        if delta
          unless interval == 'stündlich'
            new_issue = Issue.new
            new_issue.project = project
            new_issue.tracker = tracker
            new_issue.subject = subject
            new_issue.description = description
            new_issue.assigned_to = assigned_to
            new_issue.estimated_hours = estimated_hours
            new_issue.start_date = compute_start_date(delta)
            new_issue.status = IssueStatus.default
            if cf
              new_issue.custom_field_values = { cf.id => nil }
            end
            if new_issue.save
              IssueRelation.create(issue_from: new_issue, issue_to: self, relation_type: 'relates')
            end
          end
        end

        next_run = RedmineIssueRepeat::Scheduler.next_run_for(self, base_time: Time.current)
        if next_run
          RedmineIssueRepeat::IssueRepeatSchedule.create!(issue_id: id, interval: RedmineIssueRepeat::Scheduler.interval_value(self), next_run_at: next_run, anchor_day: created_on.day)
        end
      end

      def compute_start_date(delta)
        d = Date.today
        if delta == :month
          d >> 1
        else
          d + delta
        end
      end
    end
  end
end
