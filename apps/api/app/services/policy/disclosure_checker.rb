module Policy
  # spec §7: YouTube requires disclosure when AI meaningfully generates/alters
  # photorealistic content (real people, real events/places, realistic scenes).
  # Returns one of: "required" | "review" | "not_required".
  module DisclosureChecker
    module_function

    def call(project:)
      assets = project.assets.to_a

      required = assets.any? do |a|
        a.realistic && (a.represents_real_person || a.represents_real_event_or_place)
      end
      return CheckResult.new(verdict: "required", detail: "Realistic synthetic content depicts a real person, event or place.") if required

      review = assets.any? { |a| a.ai_generated && a.realistic } ||
               assets.any?(&:requires_disclosure)
      return CheckResult.new(verdict: "review", detail: "Realistic AI-generated visuals present — confirm whether disclosure applies.") if review

      CheckResult.new(verdict: "not_required", detail: "Assets are stylised or clearly synthetic; production assistance alone does not require disclosure.")
    end
  end
end
