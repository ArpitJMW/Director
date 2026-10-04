module QualityCheck
  # Task 6.1 Part B: rewrites a failed image brief POSITIVELY from the scene's
  # action and the project setting. One LLM call (free Groq planning model) per
  # repair. The reply must satisfy the contract below; if it does not, a
  # deterministic positive brief is built from the same action and setting, so
  # a repair never depends on the model obeying the format.
  class PromptRewriter
    Error = Class.new(StandardError)

    # The rewrite must contain no negation at all, and none of the words that
    # pulled the image off-era or into text.
    NEGATION = /\b(no|not|without|avoid|avoids|never|nothing|none|free|lack|lacking|cannot|don't|isn't)\b/i
    TRIGGERS = /\b(modern|contemporary|smartphones?|phones?|laptops?|screens?|news|newspapers?|headlines?|
                   chart|charts|graphs?|numbers?|text|writing|letters?|signs?|posters?|labels?|glasses|
                   sunglasses|hoodies?|sneakers?|digital|neon|cinematic|4k)\b/ix
    WORD_RANGE = (8..70)

    attr_reader :attempts

    def initialize(project:, scene:, shot: nil, provider: Providers.llm)
      @project = project
      @scene = scene
      @shot = shot
      @provider = provider
      @attempts = 0
    end

    # @param mode [String] "period" or "composition"
    # @return [Hash] { prompt:, source: "llm" | "fallback" }
    def call(problems:, mode:)
      rewritten = ask_model(problems, mode)
      return { prompt: rewritten, source: "llm" } if valid?(rewritten)

      { prompt: fallback(mode), source: "fallback" }
    rescue => e
      raise if rate_limited?(e)

      { prompt: fallback(mode), source: "fallback", error: e.message.to_s.truncate(160) }
    end

    def rate_limited?(error) = error.message.to_s.include?("429")

    # The contract, public so the spec can test it directly.
    def valid?(text)
      return false if text.blank?

      words = text.split.size
      WORD_RANGE.cover?(words) && text !~ NEGATION && text !~ TRIGGERS
    end

    # Deterministic positive brief: the action, the period clothing and
    # materials from the setting, and one lighting cue. No negatives, no triggers.
    def fallback(mode)
      s = setting
      place = s["place"].presence || "a period workshop"
      wardrobe = s["wardrobe"].presence || "period wool and linen clothing"
      lead = action.presence || "a craftsman at work"
      framing = mode == "composition" ? "wide view, hands and tools in focus" : "medium view, natural detail"
      [ lead, "in #{place}", "#{wardrobe}", framing, "warm candlelight and daylight through old glass" ].join(", ")
    end

    private

    def ask_model(problems, mode)
      @attempts += 1
      prompt = Prompts.load("quality_check_rewrite")
      result = AiGeneration.track!(
        project: @project, scene: @scene, shot: @shot, kind: "visual_prompt", provider_kind: "llm",
        provider: @provider.name, model: @provider.default_model,
        request: { prompt_version: prompt.version, mode: mode }
      ) do |_gen|
        @provider.chat(system: prompt_text(prompt.text, problems, mode), messages: [ { role: "user", content: "Rewrite the brief. Respond with JSON only." } ],
                       max_tokens: 400)
      end
      data = JSON.parse(result.text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, ""))
      data.is_a?(Hash) ? data["visual_prompt"].to_s.strip : ""
    rescue JSON::ParserError
      ""
    end

    def prompt_text(template, problems, mode)
      template
        .gsub("{action}", action.presence || "(not specified)")
        .gsub("{setting}", setting_text)
        .gsub("{current}", current_brief.to_s.truncate(400))
        .gsub("{problems}", problems.map { |p| "#{p[:issue_type]}: #{p[:evidence]}".truncate(160) }.join("; ").presence || "(none given)")
        .gsub("{mode}", mode)
    end

    def action = (@shot&.action.presence || @scene.action).to_s.strip
    def current_brief = (@shot&.visual_prompt.presence || @scene.visual_prompt)
    def setting = (@project.settings || {})["setting"].then { |s| s.is_a?(Hash) ? s : {} }

    def setting_text
      return "(none set)" if setting.empty?

      "#{setting['era']}; #{setting['place']}; wardrobe: #{setting['wardrobe']}; technology: #{setting['technology']}"
    end
  end
end
