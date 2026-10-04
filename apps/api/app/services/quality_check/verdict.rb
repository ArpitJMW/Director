module QualityCheck
  # Task 6.1 Part A: the one place that decides whether a unit fails. A unit
  # fails on any high-severity issue, or on two or more medium ones. Low issues
  # are notes. Info (informational) never counts. Vision review, the deterministic
  # checks and the runner all use this, so they cannot disagree.
  module Verdict
    module_function

    def failing?(issues)
      severities = Array(issues).map { |i| (i[:severity] || i["severity"]).to_s }
      severities.include?("high") || severities.count("medium") >= 2
    end

    def status(issues, review_status: nil)
      return "failed" if failing?(issues) || review_status == "failed"
      return "unavailable" if review_status == "unavailable"

      "passed"
    end
  end
end
