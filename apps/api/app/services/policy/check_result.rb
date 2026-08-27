module Policy
  # Outcome of a single preflight check.
  # verdict: "pass" | "warn" | "review"
  CheckResult = Data.define(:verdict, :detail, :warnings) do
    def initialize(verdict:, detail: nil, warnings: [])
      super
    end

    def self.pass(detail = nil) = new(verdict: "pass", detail: detail)
    def self.warn(detail, *warnings) = new(verdict: "warn", detail: detail, warnings: warnings.flatten)
    def self.review(detail = nil) = new(verdict: "review", detail: detail)
  end
end
