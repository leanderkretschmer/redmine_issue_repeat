module RedmineIssueRepeat
  module AutoRunner
    module_function

    def start
      return if defined?(@thread) && @thread && @thread.alive?
      @thread = Thread.new do
        loop do
          begin
            RedmineIssueRepeat::Processor.run_once
          rescue => e
            Rails.logger.error("[IssueRepeat] auto_runner error: #{e.class} #{e.message}")
          end
          sleep 10
        end
      end
    end
  end
end
