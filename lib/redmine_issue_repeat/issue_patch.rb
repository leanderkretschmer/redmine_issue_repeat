module RedmineIssueRepeat
  module IssuePatch
    def self.apply
      Issue.include InstanceMethods unless Issue < InstanceMethods
      Issue.class_eval do
        after_commit :repeat_issue_after_create, on: :create
        after_commit :update_repeat_schedule_after_update, on: :update
      end
    end

    module InstanceMethods
      def repeat_issue_after_create
        cf = IssueCustomField.find_by(name: 'Intervall')
        return unless cf
        val = custom_field_value(cf.id)
        return if val.nil? || val.to_s.strip.empty?
        interval = val.to_s.downcase
        Rails.logger.info("[IssueRepeat] create: issue=#{id} interval=#{interval}")
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
              Rails.logger.info("[IssueRepeat] create: copied new_issue=#{new_issue.id} from=#{id} start_date=#{new_issue.start_date}")
            end
          end
        end

        next_run = RedmineIssueRepeat::Scheduler.next_run_for(self, base_time: Time.current)
        Rails.logger.info("[IssueRepeat] create: computed next_run=#{next_run}") if next_run
        if next_run
          sched = RedmineIssueRepeat::IssueRepeatSchedule.create!(issue_id: id, interval: RedmineIssueRepeat::Scheduler.interval_value(self), next_run_at: next_run, anchor_day: created_on.day)
          Rails.logger.info("[IssueRepeat] create: schedule created sched=#{sched.id} issue=#{id} interval=#{sched.interval} next_run_at=#{sched.next_run_at}")
        end
      end

      def update_repeat_schedule_after_update
        cf = IssueCustomField.find_by(name: 'Intervall')
        return unless cf
        reload
        val = custom_field_value(cf.id)
        sched = RedmineIssueRepeat::IssueRepeatSchedule.find_by(issue_id: id)

        if val.nil? || val.to_s.strip.empty?
          if sched
            Rails.logger.info("[IssueRepeat] update: interval cleared, destroying schedule for issue=#{id} sched=#{sched.id}")
            sched.destroy
          else
            Rails.logger.info("[IssueRepeat] update: interval cleared, no schedule present for issue=#{id}")
          end
          return
        end

        interval = RedmineIssueRepeat::Scheduler.interval_value(self)
        return unless interval

        next_run = RedmineIssueRepeat::Scheduler.next_run_for(self, base_time: Time.current)
        if sched
          updates = {}
          updates[:interval] = interval if sched.interval != interval
          updates[:next_run_at] = next_run if next_run
          updates[:anchor_day] = created_on.day if sched.anchor_day != created_on.day
          if updates.empty?
            Rails.logger.info("[IssueRepeat] update: no changes for schedule issue=#{id} sched=#{sched.id}")
          else
            sched.update!(updates)
            Rails.logger.info("[IssueRepeat] update: schedule updated issue=#{id} sched=#{sched.id} changes=#{updates.inspect}")
          end
        else
          if next_run
            sched = RedmineIssueRepeat::IssueRepeatSchedule.create!(issue_id: id, interval: interval, next_run_at: next_run, anchor_day: created_on.day)
            Rails.logger.info("[IssueRepeat] update: schedule created sched=#{sched.id} issue=#{id} interval=#{interval} next_run_at=#{next_run}")
          else
            Rails.logger.info("[IssueRepeat] update: no next_run computed for issue=#{id} interval=#{interval}")
          end
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
