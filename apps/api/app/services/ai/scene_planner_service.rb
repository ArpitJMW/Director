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
        Split the narration into a sequence of scenes.

        visual_type is one of: #{Scene::VISUAL_TYPES.join(', ')}
        animation is one of: #{Scene::ANIMATIONS.join(', ')}
        transition is one of: #{Scene::TRANSITIONS.join(', ')}

        VISUAL DIRECTION — this matters most:
        - Most scenes should be "image" (a single AI-generated still that the
          renderer pans/zooms). Only use chart / timeline / map / quote_card when
          the beat is genuinely a data point, date sequence, location, or quote.
          Use text_animation sparingly (title cards, key stats). Never use
          screen_recording or split_screen unless the script explicitly calls for it.
        - For a documentary or real-world topic, almost every scene is "image".

        WRITING visual_prompt (for the "image" scenes):
        - Write it like a photograph brief, not a sentence of narration.
        - Always name the MAIN SUBJECT explicitly and consistently in every scene
          (e.g. "an adult male Bengal tiger, deep orange coat with black stripes"),
          so the subject looks the same across the video.
        - Include: subject + setting + time of day / weather + camera angle or shot
          type (wide / close-up / low angle / aerial) + mood/lighting.
        - Concrete and specific. No abstract concepts, no on-screen text, no people
          unless the script needs them.
        - Do NOT add style words like "cinematic" or "4k" — the studio applies the
          project's visual style automatically.

        Other rules:
        - Scene durations sum to roughly the target duration.
        - narration is drawn from the script; captions are short (<= 6 words).
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
      parts << "Topic / niche: #{@project.niche}" if @project.niche.present?
      parts << "Visual style: #{@project.visual_style.tr('_', ' ')}"
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
