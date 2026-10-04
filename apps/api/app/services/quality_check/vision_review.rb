module QualityCheck
  # Task 6 Part B: a free vision model reviews one generated image against its
  # narration, action and the project setting. Output is parsed defensively and
  # a failure here never blocks the pipeline: the unit is just marked
  # "unavailable". A 429 is re-raised so the caller can stop the run.
  class VisionReview
    ISSUE_TYPES = %w[gibberish_text fake_chart_or_data era_mismatch subject_mismatch
                     anatomy unsafe letterbox other].freeze
    SEVERITIES = %w[low medium high].freeze
    EVIDENCE_LIMIT = 240

    Error = Class.new(StandardError)

    Review = Data.define(:status, :issues, :error)

    def initialize(project:, scene:, shot: nil, reviewer: Providers.qa)
      @project = project
      @scene = scene
      @shot = shot
      @reviewer = reviewer
    end

    # @param asset [Asset] the image to review
    # @return [Review] status is "passed", "failed" or "unavailable"
    def call(asset:)
      bytes = File.binread(Rails.root.join("storage", "uploads", asset.storage_key).to_s)
      prompt = Prompts.load("quality_check") # latest version (v2: severity rules)
      result = AiGeneration.track!(
        project: @project, scene: @scene, shot: @shot, kind: "quality_check", provider_kind: "llm",
        provider: @reviewer.name, model: @reviewer.default_model,
        request: { prompt_version: prompt.version, unit: unit_key }
      ) do |_gen|
        @reviewer.review(image_bytes: bytes, content_type: asset.content_type || "image/jpeg",
                         prompt: build_prompt(prompt.text))
      end

      verdict = parse(result.text)
      Review.new(status: Verdict.status(verdict[:issues]), issues: verdict[:issues], error: nil)
    rescue Providers::Qa::GeminiVisionAdapter::RateLimited
      raise
    rescue => e
      Review.new(status: "unavailable", issues: [], error: e.message.to_s.truncate(200))
    end

    def unit_key = (@shot || @scene).key

    def build_prompt(template)
      template
        .gsub("{narration}", @scene.narration.to_s.truncate(400).presence || "(none)")
        .gsub("{action}", (@shot&.action.presence || @scene.action.presence || "(not specified)").to_s)
        .gsub("{setting}", setting_text)
    end

    def setting_text
      s = (@project.settings || {})["setting"]
      return "(none set)" unless s.is_a?(Hash)

      "#{s['era']}; #{s['place']}; wardrobe: #{s['wardrobe']}; technology: #{s['technology']}; avoid: #{Array(s['avoid']).join(', ')}"
    end

    # Accepts a JSON object whose "issues" is an array. The verdict is derived
    # from the issues' severities (Verdict), not from any pass flag the model
    # wrote, so a model cannot pass an image its own issues would fail.
    def parse(text)
      json = text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      data = JSON.parse(json)
      raise Error, "reply is not a JSON object" unless data.is_a?(Hash)
      raise Error, "reply has no issues array" unless data["issues"].is_a?(Array)

      issues = data["issues"].filter_map { |raw| normalize(raw) }
      { pass: !Verdict.failing?(issues), issues: issues }
    rescue JSON::ParserError => e
      raise Error, "reply did not parse: #{e.message.truncate(120)}"
    end

    def normalize(raw)
      return nil unless raw.is_a?(Hash)

      type = raw["type"].to_s
      severity = raw["severity"].to_s
      {
        unit_key: unit_key, scene_key: @scene.key, shot_key: @shot&.key,
        issue_type: ISSUE_TYPES.include?(type) ? type : "other",
        severity: SEVERITIES.include?(severity) ? severity : "medium",
        evidence: raw["evidence"].to_s.strip.truncate(EVIDENCE_LIMIT),
        source: "vision"
      }
    end
  end
end
