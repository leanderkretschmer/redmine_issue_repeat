module RedmineIssueRepeat
  module IssuePatch
    def self.apply
      Rails.logger.info("[IssueRepeat] apply: no callbacks, task-driven scheduling enabled")
    end

  end
end
