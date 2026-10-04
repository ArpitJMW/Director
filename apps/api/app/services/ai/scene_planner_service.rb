module Ai
  # Scene planner + visual director (planning-doc §7). Turns the current script
  # into an ordered set of SCENES — meaningful story beats, not one scene per
  # sentence. Each scene carries production direction (purpose, action, camera
  # intent, mood, subject/environment continuity). Full replace on regeneration.
  # Shots are added afterwards by Ai::ShotPlanner.
  class ScenePlannerService
    Error = Class.new(StandardError)

    def initialize(project:, provider: Providers.llm)
      @project = project
      @provider = provider
      @script = project.current_script
    end

    def call
      raise Error, "project has no current script" if @script.nil?

      prompt = Prompts.load("scene_planner")
      system = prompt.text
        .gsub("{visual_types}", Scene::PLANNABLE_VISUAL_TYPES.join(", "))
        .gsub("{animations}", Scene::ANIMATIONS.join(", "))
        .gsub("{transitions}", Scene::TRANSITIONS.join(", "))
        .gsub("{camera_motions}", Scene::CAMERA_MOTIONS.join(", "))
        .gsub("{camera_intensities}", Scene::CAMERA_INTENSITIES.join(", "))
        .gsub("{overlay_types}", Scene::OVERLAY_TYPES.join(", "))
        .gsub("{text_styles}", Scene::TEXT_STYLES.join(", "))

      generation = nil
      result = AiGeneration.track!(
        project: @project, kind: "scene_plan", provider: @provider.name,
        model: @provider.default_model,
        request: { script_id: @script.public_id, prompt_version: prompt.version }
      ) do |gen|
        generation = gen
        @provider.chat(
          system: system,
          messages: [ { role: "user", content: user_prompt } ],
          max_tokens: 6954
        )
      end

      replace_scenes(parse(result.text), generation)
    end

    private

    def user_prompt
      parts = []
      parts << "Title: #{@script.selected_title}"
      parts << "Story angle: #{@script.story_angle}"
      parts << "Topic / niche: #{@project.niche}" if @project.niche.present?
      parts << "Visual style: #{@project.visual_style.tr('_', ' ')}"
      parts << "Target duration: #{@project.target_duration_seconds} seconds"
      parts << "Format: #{@project.format} (#{@project.aspect_ratio})"
      parts << "Creative notes (visual direction lives here): #{@script.creative_notes}" if @script.creative_notes.present?
      parts << "Creator instructions: #{@project.creator_instructions}" if @project.creator_instructions.present?
      parts << "\nFull narration:\n#{@script.full_narration}"
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
      raise Error, "scene plan JSON has no scenes array" unless scenes.is_a?(Array) && scenes.any?

      scenes
    rescue JSON::ParserError => e
      raise Error, "scene plan JSON did not parse: #{e.message}"
    end

    def replace_scenes(scenes_data, generation)
      durations = timed_durations(scenes_data)
      @project.transaction do
        @project.scenes.destroy_all

        scenes_data.each_with_index.map do |raw, index|
          key = format("scene_%02d", index + 1)
          direction = DirectionParser.new(project: @project, unit_key: key).parse(raw["direction"])
          camera = sanitize_hash(raw["camera"])
          camera["movement"] = direction[:camera_movement] if direction[:camera_movement]
          visual_type = coerce_visual_type(raw["visual_type"], key)
          asset_strategy = coerce(raw["asset_strategy"], Scene::ASSET_STRATEGIES, "image")
          visual_type, asset_strategy = guard_chart(visual_type, asset_strategy, key)

          @project.scenes.create!(
            script: @script,
            position: index + 1,
            key: key,
            purpose: raw["purpose"],
            narration: raw["narration"],
            caption: raw["caption"],
            duration_seconds: durations[index],
            content_type: raw["content_type"].presence,
            visual_type: visual_type,
            asset_strategy: asset_strategy,
            action: raw["action"],
            camera: camera,
            motion: { "intensity" => direction[:intensity] }.compact,
            mood: raw["mood"],
            visual_prompt: raw["visual_prompt"],
            negative_prompt: raw["negative_prompt"],
            animation: coerce(raw["animation"], Scene::ANIMATIONS, "ken_burns"),
            # Task 4: prefer the Director's own transition_in choice; the old
            # top-level "transition" field is still honoured as a fallback so
            # a prompt that only sets one or the other keeps working.
            transition: direction[:transition] || coerce(raw["transition"], Scene::TRANSITIONS, "fade"),
            background_music_level: clamp_level(raw["background_music_level"]),
            status: "pending",
            metadata: {
              ai_generation_id: generation.id,
              subject: raw["subject"].to_s.strip.presence,
              environment: raw["environment"].to_s.strip.presence,
              # Why the planner chose this scene's visual_type/asset_strategy
              # (scene_planner prompt v2+). Absent for plans made under v1.
              visual_reason: raw["visual_reason"].to_s.strip.presence,
              # Phase 1 Task 4 — why THIS direction (camera/transition/overlay/
              # text_style) was chosen, separate from visual_reason above.
              direction_reason: direction[:direction_reason],
              overlay: direction[:overlay],
              # Media::TextAnimationSpecService (text units only) reads this.
              direction_text: {
                "text_style" => direction[:text_style], "items" => direction[:items],
                "number" => direction[:number], "unit" => direction[:unit]
              }.compact.presence
            }.compact
          )
        end
      end
    end

    def coerce(value, allowed, fallback)
      allowed.include?(value) ? value : fallback
    end

    # Phase 1 Task 4.2 Part B: visual_type must be one the studio can
    # actually produce (Scene::PLANNABLE_VISUAL_TYPES — Media::
    # ProductionDispatcher only ever routes to an image or a text unit, so
    # anything else, e.g. "generated_video", just silently became a plain
    # image before this). Same "invalid -> default + logged warning, never
    # silent" pattern as Ai::DirectionParser; blank is normal (planner just
    # didn't set it) and isn't logged, only a present-but-unplannable value is.
    # Task 6 A3: a chart beat must never reach the image model. Image generation
    # invents numbers and labels for a chart, so a chart that would be imaged is
    # routed to the text path (the number, or the list, is shown as text instead).
    def guard_chart(visual_type, asset_strategy, key)
      return [ visual_type, asset_strategy ] unless visual_type == "chart" && asset_strategy == "image"

      GenerationLog.create!(
        project: @project, level: "warn", stage: "direction",
        message: "#{key}: visual_type 'chart' would reach the image model; routed to text instead"
      )
      [ "text_animation", "text" ]
    end

    def coerce_visual_type(value, key)
      return "image" if value.blank?
      return value if Scene::PLANNABLE_VISUAL_TYPES.include?(value)

      GenerationLog.create!(
        project: @project, level: "warn", stage: "direction",
        message: "#{key}: invalid visual_type #{value.inspect} (no executor), falling back to image"
      )
      "image"
    end

    def sanitize_hash(value)
      return {} unless value.is_a?(Hash)

      value.slice("shot_type", "movement", "framing").compact
    end

    # Task 7.2 Part C: the model's per-scene seconds drifted (one printing-press
    # plan summed to 24s for a 45s target). Timing now follows the narration:
    # each scene takes its share of the target in proportion to its narration
    # word count. The model's own number is only a fallback when no scene has
    # any narration to share out.
    def timed_durations(scenes_data)
      words = scenes_data.map { |raw| raw["narration"].to_s.split.size }
      total_words = words.sum
      target = @project.target_duration_seconds.to_f
      return scenes_data.map { |raw| clamp_duration(raw["duration_seconds"]) } if total_words.zero? || target <= 0

      words.map { |count| (target * count / total_words).round(1).clamp(1.0, 120.0) }
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
