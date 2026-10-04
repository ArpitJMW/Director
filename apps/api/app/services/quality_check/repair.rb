module QualityCheck
  # Task 6.1 Part B: repair by strategy, chosen from the issue type, instead of
  # appending a negative hint to the old prompt.
  #
  #   chart / fake data .......... text_conversion: no image at all; the unit
  #                                becomes a text beat (big number from narration)
  #   era / subject / anatomy /
  #   unsafe / other ............. prompt_rewrite (period): one positive rewrite
  #                                from action + setting, setting first
  #   gibberish_text ............. prompt_rewrite (composition): a framing with no
  #                                flat writable surface facing camera
  #   audio_missing .............. audio_regenerate (single-scene voice call)
  #
  # One attempt per unit, and QA_MAX_REPAIRS (default 6) repaired units per
  # project. Failed attempts count too, since each one spends a provider call.
  class Repair
    # A 429 from a provider stops the whole run, not just this unit.
    Stop = Class.new(StandardError)

    MAX_PER_UNIT = 1
    CHART_TYPES = %w[fake_chart_or_data chart_routed_to_image].freeze
    IMAGE_TYPES = %w[era_mismatch subject_mismatch anatomy unsafe letterbox other gibberish_text].freeze

    def self.max_per_project = ENV.fetch("QA_MAX_REPAIRS", "6").to_i

    def initialize(project:, provider: Providers.image, voice: Providers.voice, rewriter: nil)
      @project = project
      @provider = provider
      @voice = voice
      @rewriter = rewriter
    end

    # @return [Hash] { outcome:, types:, strategy:, ... }
    def call(unit:, scene:, shot:, issues:)
      types = issues.map { |i| i[:issue_type] }.uniq
      return outcome("skipped_unit_limit", types) if Store.repair_attempts(unit) >= MAX_PER_UNIT
      return outcome("skipped_project_limit", types) if project_repairs_used >= self.class.max_per_project

      parts = []
      parts << repair_audio(scene) if types.include?("audio_missing")
      if types.any? { |t| CHART_TYPES.include?(t) }
        parts << convert_to_text(scene, shot)
      elsif types.any? { |t| IMAGE_TYPES.include?(t) }
        mode = types.include?("gibberish_text") ? "composition" : "period"
        parts << rewrite_image(scene, shot, issues, mode)
      end
      return outcome("failed", types, strategy: "none") if parts.empty?

      outcome(parts.all? { |p| p[:outcome] == "repaired" } ? "repaired" : "failed", types,
              strategy: parts.map { |p| p[:strategy] }.join("+"),
              positive: parts.filter_map { |p| p[:positive] }.first,
              error: parts.filter_map { |p| p[:error] }.first)
    end

    # Repaired-or-attempted units across the project. Each counts once.
    def project_repairs_used
      units = @project.scenes.includes(:shots).flat_map { |s| [ s, *s.shots.to_a ] }
      units.count { |u| Store.repair_attempts(u).positive? }
    end

    private

    def rewriter_for(scene, shot)
      @rewriter || PromptRewriter.new(project: @project, scene: scene, shot: shot)
    end

    def rewrite_image(scene, shot, issues, mode)
      rewritten = rewriter_for(scene, shot).call(problems: issues, mode: mode)
      Media::ImageGenerationService.new(scene: scene, shot: shot, provider: @provider,
                                        brief_override: rewritten[:prompt], setting_first: true).call
      { outcome: "repaired", strategy: "prompt_rewrite:#{mode}:#{rewritten[:source]}", positive: rewritten[:prompt] }
    rescue => e
      raise Stop, e.message if rate_limited?(e)

      { outcome: "failed", strategy: "prompt_rewrite:#{mode}", error: e.message.to_s.truncate(200) }
    end

    # A statistic beat is shown as text, not as an invented chart. The first
    # number in the narration becomes the big number; with no number, the
    # narration itself is shown as staggered text.
    def convert_to_text(scene, shot)
      return { outcome: "failed", strategy: "text_conversion", error: "chart on a single shot is not converted" } if shot

      number, unit = number_from(scene.narration.to_s)
      direction = if number
                    { "text_style" => "big_number", "number" => number, "unit" => unit }.compact
                  else
                    { "text_style" => "stagger_reveal" }
                  end
      scene.shots.destroy_all
      scene.update!(asset_strategy: "text", visual_type: "text_animation", selected_asset: nil,
                    metadata: scene.metadata.merge("direction_text" => direction))
      Media::TextAnimationSpecService.new(scene: scene).call
      GenerationLog.create!(project: @project, scene: scene, level: "warn", stage: "quality_check",
                            message: "#{scene.key}: chart image replaced by a text beat (#{direction['text_style']})")
      { outcome: "repaired", strategy: "text_conversion:#{direction['text_style']}" }
    rescue => e
      { outcome: "failed", strategy: "text_conversion", error: e.message.to_s.truncate(200) }
    end

    def number_from(text)
      match = text.match(/(\d[\d,]*(?:\.\d+)?)\s*(%|percent|times|years|million|billion)?/i)
      return [ nil, nil ] unless match

      digits = match[1].delete(",")
      [ digits.include?(".") ? digits.to_f : digits.to_i, match[2]&.sub("percent", "%") ]
    end

    def repair_audio(scene)
      Media::VoiceGenerationService.new(scene: scene, provider: @voice).call
      { outcome: "repaired", strategy: "audio_regenerate" }
    rescue => e
      raise Stop, e.message if rate_limited?(e)

      { outcome: "failed", strategy: "audio_regenerate", error: e.message.to_s.truncate(200) }
    end

    def rate_limited?(error)
      error.is_a?(Providers::Qa::GeminiVisionAdapter::RateLimited) || error.message.to_s.include?("429")
    end

    def outcome(result, types, extra = {})
      { outcome: result, types: types }.merge(extra.compact)
    end
  end
end
