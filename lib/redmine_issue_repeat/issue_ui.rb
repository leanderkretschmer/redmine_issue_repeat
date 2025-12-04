module RedmineIssueRepeat
  module IssueUi
    def self.copy_issue?(issue)
      return false unless issue.is_a?(Issue)
      rels = IssueRelation.where(issue_from_id: issue.id, relation_type: 'relates')
      return false if rels.empty?
      related_to_ids = rels.map(&:issue_to_id)
      RedmineIssueRepeat::IssueRepeatSchedule.where(issue_id: related_to_ids).exists?
    end
  end
end

