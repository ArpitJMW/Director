module Ai
  # Script Engine (spec §22). Turns a project's inputs (+ research sources) into a
  # structured script and persists it as the new current Script.
  class ScriptService
    Error = Class.new(StandardError)

    REQUIRED_KEYS = %w[title_options selected_title hook story_angle sections full_narration].freeze

    def initialize(project:, provider: Providers.llm)
      @project = project
      @provider = provider
    end

    def call
      generation = nil
      result = AiGeneration.track!(
        project: @project, kind: "script", provider: @provider.name,
        model: @provider.default_model, request: { topic: @project.topic }
      ) do |gen|
        generation = gen
        @provider.chat(
          system: system_prompt,
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

      build_script(data, generation)
    end

    private

    def system_prompt
      <<~PROMPT
        You are the script engine for an AI video studio. Write an original, well-structured
        narration script for a faceless YouTube video.

        Principles:
        - Originality first: substantive creative/educational value; never a generic listicle.
        - Do not copy source text; synthesise and attribute claims to sources by index.
        - The narration must carry real narrative or educational value on its own.
        - Match the requested duration, tone and audience.

        Respond with ONLY a single JSON object, no markdown fences, matching:
        {
          "title_options": ["...", "...", "..."],
          "selected_title": "...",
          "hook": "one or two sentences",
          "story_angle": "the unique angle for this video",
          "sections": [{ "heading": "...", "narration": "..." }],
          "full_narration": "the complete narration text, concatenated",
          "estimated_duration_seconds": 0,
          "creative_notes": "notes for the storyboard stage",
          "claims": [{ "text": "...", "source_indexes": [0] }]
        }
      PROMPT
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
