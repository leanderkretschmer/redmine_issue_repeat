module RedmineIssueRepeat
  module ChecklistCopy
    module_function

    def copy_from(source_issue, target_issue)
      return unless source_issue && target_issue
      if defined?(Checklist) && source_issue.respond_to?(:checklists) && target_issue.respond_to?(:checklists)
        source_issue.checklists.order(:position).each do |item|
          target_issue.checklists.build(subject: item.subject, is_done: false, position: item.position)
        end
        target_issue.checklists.each(&:save)
      elsif defined?(IssueChecklist) && source_issue.respond_to?(:issue_checklists) && target_issue.respond_to?(:issue_checklists)
        source_issue.issue_checklists.order(:position).each do |item|
          target_issue.issue_checklists.build(subject: item.subject, is_done: false, position: item.position)
        end
        target_issue.issue_checklists.each(&:save)
      end
    end
  end
end