module Policy
  # Assembles the YouTube-oriented preflight report (spec §32). Internal
  # heuristic only — never a monetization guarantee.
  class PreflightEngine
    CHECKS = {
      "originality" => OriginalityChecker,
      "narrative_value" => NarrativeValueChecker,
      "repetition_risk" => RepetitionChecker,
      "asset_provenance" => ProvenanceChecker,
      "reuse_risk" => ReuseChecker,
      "copyright_license" => CopyrightChecker
    }.freeze

    # Checks that gate the "ready" status.
    GATING = CHECKS.keys.freeze

    def initialize(project:, video_render: nil)
      @project = project
      @video_render = video_render
    end

    def call
      results = CHECKS.transform_values { |checker| checker.call(project: @project) }
      disclosure = DisclosureChecker.call(project: @project)

      checks = results.transform_values(&:verdict)
      checks["advertiser_suitability"] = "review"

      warnings = results.flat_map do |key, result|
        result.warnings.map { |w| { check: key, message: w } }
      end

      ready =
        GATING.all? { |key| checks[key] == "pass" } &&
        disclosure.verdict == "not_required" &&
        warnings.empty?

      @project.preflight_reports.create!(
        video_render: @video_render,
        status: ready ? "ready" : "review_required",
        checks: checks,
        ai_disclosure: disclosure.verdict,
        warnings: warnings,
        generated_by_generation: @project.ai_generations.where(kind: "preflight").order(:created_at).last
      )
    end
  end
end
