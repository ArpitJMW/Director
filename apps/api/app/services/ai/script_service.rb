module Ai
  # Script Engine (spec §22). Turns a project's inputs (+ research sources) into a
  # structured script and persists it as the new current Script.
  class ScriptService
    Error = Class.new(StandardError)

    REQUIRED_KEYS = %w[title_options selected_title hook story_angle sections full_narration].freeze

    # Phase 1 Task 4.2 — measured directly from every real Gemini TTS
    # narration produced so far (30 VoiceGeneration rows across 8 real
    # projects, Tasks 2.5-4): total spoken words / total measured audio
    # seconds = 2.2189 wps (a plain per-row average of the same rows comes
    # out to 2.2246 — close enough that either is a fine estimate; the
    # duration-weighted total is used since it isn't skewed by short scenes).
    # See the Task 4.2 final report for the full per-scene table.
    MEASURED_WORDS_PER_SECOND = 2.22
    # Budget = target seconds * measured wps, then trimmed a bit further —
    # scripts should undershoot, never overshoot (Task 4.2 Part A).
    BUDGET_SAFETY_MARGIN = 0.95
    # Task 6.1 Part C: boundary/scene arithmetic for the word budget.
    BOUNDARY_GAP_SECONDS = 0.45
    SCENE_SECONDS_ESTIMATE = 6.0
    MIN_ESTIMATED_SCENES = 4
    MAX_ESTIMATED_SCENES = 10
    # Only worth a whole extra LLM call (and its own risk of drifting the
    # story) when the overage is more than noise — 10% over budget or more.
    CONDENSE_OVERAGE_THRESHOLD = 1.10
    # Task 6.2 Part B: below this share of the budget, one expand pass runs.
    EXPAND_UNDERSHOOT_THRESHOLD = 0.90

    def initialize(project:, provider: Providers.llm)
      @project = project
      @provider = provider
    end

    def call
      apply_duration_hint!
      budget = word_budget
      prompt = Prompts.load("script")
      system = prompt.text.gsub("{word_budget}", budget.to_s)
              .gsub("{word_target_low}", (budget * 0.95).round.to_s)

      generation = nil
      result = AiGeneration.track!(
        project: @project, kind: "script", provider: @provider.name,
        model: @provider.default_model,
        request: { topic: @project.topic, prompt_version: prompt.version, word_budget: budget }
      ) do |gen|
        generation = gen
        @provider.chat(
          system: system,
          messages: [ { role: "user", content: user_prompt } ],
          max_tokens: 4000
        )
      end

      data =
        begin
          parse(result.text)
        rescue Error => e
          generation&.update(status: "failed", failure_reason: e.message)
          raise
        end

      data = enforce_word_budget(data, budget)

      build_script(data, generation)
    end

    private

    def word_budget
      self.class.word_budget_for(@project.target_duration_seconds)
    end

    # Task 6.1 Part C: speech only fills part of the target. Each scene boundary
    # adds ~0.45s of pause/transition that no word can use, so the budget
    # subtracts that before converting seconds to words. Scene count is estimated
    # from the target (one scene per ~6s, bounded), because the real count is
    # decided later by the planner.
    def self.word_budget_for(target_seconds)
      target = target_seconds.to_f
      scenes = (target / SCENE_SECONDS_ESTIMATE).round.clamp(MIN_ESTIMATED_SCENES, MAX_ESTIMATED_SCENES)
      speech_seconds = target - (scenes * BOUNDARY_GAP_SECONDS)
      (speech_seconds * MEASURED_WORDS_PER_SECOND * BUDGET_SAFETY_MARGIN).round
    end

    # Logs actual vs budget every time (Task 4.2 Part A.1), and does AT MOST
    # one condense pass — never more, even if the condensed draft is still
    # over. A second automatic pass risks eroding the story further for
    # diminishing returns; a still-over condensed draft is logged and kept.
    def enforce_word_budget(data, budget)
      words = narration_word_count(data)
      GenerationLog.create!(
        project: @project, level: "info", stage: "script",
        message: "narration is #{words} words vs a #{budget}-word budget " \
                 "(target #{@project.target_duration_seconds}s at #{MEASURED_WORDS_PER_SECOND} wps)"
      )
      # Task 6.2 Part B: the budget is a target range. Below 90% of it, one
      # expand pass; 90% to 110%, accepted as is; above 110%, the condense pass.
      if words < budget * EXPAND_UNDERSHOOT_THRESHOLD
        expanded = expand(data, budget)
        return expanded || data
      end
      return data if words <= budget * CONDENSE_OVERAGE_THRESHOLD

      condensed = condense(data, budget)
      condensed || data
    end

    # Task 6.2 Part B: ONE expand pass, mirroring condense. It runs at most once,
    # and a failure keeps the original short script (logged).
    def expand(data, budget)
      prompt = Prompts.load("script_expand")
      generation = nil
      result = AiGeneration.track!(
        project: @project, kind: "script_expand", provider: @provider.name,
        model: @provider.default_model,
        request: { word_budget: budget, prompt_version: prompt.version }
      ) do |gen|
        generation = gen
        @provider.chat(
          system: prompt.text,
          messages: [ { role: "user", content: expand_user_prompt(data, budget) } ],
          max_tokens: 4000
        )
      end

      expanded = parse(result.text)
      GenerationLog.create!(
        project: @project, level: "info", stage: "script",
        message: "expand pass: #{narration_word_count(data)} -> #{narration_word_count(expanded)} words (target #{(budget * 0.95).round}-#{budget})"
      )
      expanded
    rescue => e
      generation&.update(status: "failed", failure_reason: e.message)
      GenerationLog.create!(
        project: @project, level: "warn", stage: "script",
        message: "expand pass failed (#{e.message}); keeping the #{narration_word_count(data)}-word original"
      )
      nil
    end

    def expand_user_prompt(data, budget)
      "Original script JSON:\n#{data.to_json}\n\n" \
      "Expand full_narration to between #{(budget * 0.95).round} and #{budget} words " \
      "(currently #{narration_word_count(data)})."
    end

    def narration_word_count(data)
      data["full_narration"].to_s.split.size
    end

    def condense(data, budget)
      prompt = Prompts.load("script_condense")
      generation = nil
      result = AiGeneration.track!(
        project: @project, kind: "script_condense", provider: @provider.name,
        model: @provider.default_model,
        request: { word_budget: budget, prompt_version: prompt.version }
      ) do |gen|
        generation = gen
        @provider.chat(
          system: prompt.text,
          messages: [ { role: "user", content: condense_user_prompt(data, budget) } ],
          max_tokens: 4000
        )
      end

      condensed = parse(result.text)
      GenerationLog.create!(
        project: @project, level: "info", stage: "script",
        message: "condense pass: #{narration_word_count(data)} -> #{narration_word_count(condensed)} words (budget #{budget})"
      )
      condensed
    rescue => e
      generation&.update(status: "failed", failure_reason: e.message)
      GenerationLog.create!(
        project: @project, level: "warn", stage: "script",
        message: "condense pass failed (#{e.message}); keeping the #{narration_word_count(data)}-word original"
      )
      nil
    end

    def condense_user_prompt(data, budget)
      "Original script JSON:\n#{data.to_json}\n\n" \
      "Word budget for full_narration: #{budget} (currently #{narration_word_count(data)})."
    end

    # If the user stated a length in their own words ("a 30-40 second video"),
    # honour it over the form default so every downstream stage sizes to it.
    def apply_duration_hint!
      hint = Ai::DurationHint.parse(@project.topic, @project.creator_instructions)
      return unless hint && hint != @project.target_duration_seconds

      @project.update_column(:target_duration_seconds, hint)
    end

    def user_prompt
      parts = []
      parts << "Topic: #{@project.topic.presence || @project.title}"
      parts << "Working title: #{@project.title}"
      parts << "Niche: #{@project.niche}" if @project.niche.present?
      parts << "Audience: #{@project.audience}" if @project.audience.present?
      parts << "Tone: #{@project.tone}" if @project.tone.present?
      parts << "Target duration: #{@project.target_duration_seconds} seconds"
      parts << "Format: #{@project.format}"
      parts << "Creator instructions: #{@project.creator_instructions}" if @project.creator_instructions.present?

      sources = @project.sources.order(:created_at)
      if sources.any?
        parts << "\nResearch sources (cite by index):"
        sources.each_with_index do |source, i|
          parts << "[#{i}] #{source.title} — #{source.url} (#{source.publisher})"
          parts << "    #{source.summary}" if source.summary.present?
        end
      end

      parts.join("\n")
    end

    def parse(text)
      json = text.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      data = JSON.parse(json)
      missing = REQUIRED_KEYS - data.keys
      raise Error, "script JSON missing keys: #{missing.join(', ')}" if missing.any?

      data
    rescue JSON::ParserError => e
      raise Error, "script JSON did not parse: #{e.message}"
    end

    def build_script(data, generation)
      @project.scripts.create!(
        current: true,
        source_type: "ai_generated",
        ai_generation: generation,
        title_options: Array(data["title_options"]),
        selected_title: data["selected_title"],
        hook: data["hook"],
        story_angle: data["story_angle"],
        sections: Array(data["sections"]),
        full_narration: data["full_narration"],
        estimated_duration_seconds: data["estimated_duration_seconds"],
        creative_notes: data["creative_notes"],
        claims: Array(data["claims"])
      )
    end
  end
end
