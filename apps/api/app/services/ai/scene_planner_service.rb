module Ai
  # Storyboard builder + Visual Director (spec §20 steps 7-9, §23). Turns the
  # current script into an ordered set of scenes following the Scene JSON
  # contract (§19). Full replace on regeneration.
  class ScenePlannerService
    Error = Class.new(StandardError)

    def initialize(project:, provider: Providers.llm)
      @project = project
      @provider = provider
      @script = project.current_script
    end

    def call
      raise Error, "project has no current script" if @script.nil?

      generation = nil
      result = AiGeneration.track!(
        project: @project, kind: "scene_plan", provider: @provider.name,
        model: @provider.default_model, request: { script_id: @script.public_id }
      ) do |gen|
        generation = gen
        @provider.chat(
          system: system_prompt,
          messages: [ { role: "user", content: user_prompt } ],
          max_tokens: 4000
        )
      end

      scenes_data = parse(result.text)
      replace_scenes(scenes_data, generation)
    end

    private

    def system_prompt
      <<~PROMPT
        You are the storyboard engine and visual director for an AI video studio.
        Split the narration into a sequence of scenes. Do NOT generate one image
        per sentence — as visual director, choose the most useful visual treatment
        for each beat and deliberately vary it across the video.

        visual_type is one of: #{Scene::VISUAL_TYPES.join(', ')}
        animation is one of: #{Scene::ANIMATIONS.join(', ')}
        transition is one of: #{Scene::TRANSITIONS.join(', ')}

        Rules:
        - Scene durations should sum to roughly the target duration.
        - Every scene has narration drawn from (not copied verbatim beyond) the script.
        - visual_prompt describes what to generate/show; keep captions short.
        - background_music_level is 0..1 (typically 0.10–0.20).

        Respond with ONLY a JSON object: { "scenes": [ { "narration": "...",
        "visual_type": "...", "visual_prompt": "...", "caption": "...",
        "duration_seconds": 0, "animation": "...", "transition": "...",
        "background_music_level": 0.15 } ] }
      PROMPT
    end

    def user_prompt
      parts = []
      parts << "Title: #{@script.selected_title}"
      parts << "Story angle: #{@script.story_angle}"
      parts << "Target duration: #{@project.target_duration_seconds} seconds"
      parts << "Format: #{@project.format} (#{@project.aspect_ratio})"
      parts << "Creative notes: #{@script.creative_notes}" if @script.creative_notes.present?
      parts << "\nNarration:\n#{@script.full_narration}"
      if @script.sections.present?
        parts << "\nSections:"
        @script.sections.each { |s| parts << "- #{s['heading']}: #{s['narration']}" }
      end
      parts.join("\n")
    end

    def parse(text)
      json = text.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      data = JSON.parse(json)
      scenes = data["scenes"]
      raise Error, "storyboard JSON has no scenes array" unless scenes.is_a?(Array) && scenes.any?

      scenes
    rescue JSON::ParserError => e
      raise Error, "storyboard JSON did not parse: #{e.message}"
    end

    def replace_scenes(scenes_data, generation)
      @project.transaction do
        @project.scenes.destroy_all

        scenes_data.each_with_index.map do |raw, index|
          @project.scenes.create!(
            script: @script,
            position: index + 1,
            key: format("scene_%02d", index + 1),
            narration: raw["narration"],
            visual_type: coerce(raw["visual_type"], Scene::VISUAL_TYPES, "image"),
            visual_prompt: raw["visual_prompt"],
            caption: raw["caption"],
            duration_seconds: clamp_duration(raw["duration_seconds"]),
            animation: coerce(raw["animation"], Scene::ANIMATIONS, "ken_burns"),
            transition: coerce(raw["transition"], Scene::TRANSITIONS, "fade"),
            background_music_level: clamp_level(raw["background_music_level"]),
            status: "pending",
            metadata: { ai_generation_id: generation.id }
          )
        end
      end
    end

    def coerce(value, allowed, fallback)
      allowed.include?(value) ? value : fallback
    end

    def clamp_duration(value)
      [ [ value.to_f, 1.0 ].max, 120.0 ].min
    end

    def clamp_level(value)
      return 0.15 if value.nil?

      [ [ value.to_f, 0.0 ].max, 1.0 ].min
    end
  end
end
