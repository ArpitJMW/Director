module Ai
  # Shot planner (planning-doc §7). Breaks scenes into 1-4 shots — different
  # framings of the same story beat — so a beat that sits on screen for more than
  # a few seconds still has visual movement.
  #
  #   Ai::ShotPlanner.new(project: p).call         # batched — all eligible scenes, one LLM call
  #   Ai::ShotPlanner.new(scene: s).call           # just this scene (regeneration)
  #
  # Idempotent per scene: replaces that scene's shots on each run. Non-image
  # scenes are left without shots (the renderer handles them at scene level).
  class ShotPlanner
    Error = Class.new(StandardError)

    MAX_SHOTS = 4
    # Scenes at or below this render fine as one image.
    MIN_SPLIT_SECONDS = 7.0

    def initialize(project: nil, scene: nil, provider: Providers.llm)
      @scene = scene
      @project = project || scene&.project
      @provider = provider
      raise ArgumentError, "need a project or a scene" if @project.nil?
    end

    def call
      scenes = target_scenes
      return [] if scenes.empty?

      prompt = Prompts.load("shot_planner")
      result = AiGeneration.track!(
        project: @project, scene: @scene, kind: "shot_plan", provider: @provider.name,
        model: @provider.default_model,
        request: { scenes: scenes.map(&:key), prompt_version: prompt.version }
      ) do |_gen|
        @provider.chat(
          system: prompt.text,
          messages: [ { role: "user", content: user_prompt(scenes) } ],
          max_tokens: 4000
        )
      end

      by_key = parse(result.text)
      scenes.flat_map { |scene| replace_shots(scene, by_key[scene.key]) }
    end

    private

    def target_scenes
      if @scene
        plannable?(@scene) ? [ @scene ] : []
      else
        @project.scenes.order(:position).select do |s|
          plannable?(s) && estimated_seconds(s) > MIN_SPLIT_SECONDS
        end
      end
    end

    # Task 5C: the split decision uses how long the narration will actually
    # run (words / measured speaking rate), not the planner's pre-TTS
    # duration — that duration was what let a 10s held image through.
    def estimated_seconds(scene)
      words = scene.narration.to_s.split.size
      return scene.duration_seconds.to_f if words.zero?

      words / Ai::ScriptService::MEASURED_WORDS_PER_SECOND
    end

    # Same reasoning as Media::ImageGenerationService#generatable? (Phase 1
    # Task 2.3): asset_strategy is the production decision, not visual_type —
    # a "chart" scene with asset_strategy "image" gets an image and should be
    # eligible for shot-splitting exactly like any other image scene.
    def plannable?(scene)
      scene.asset_strategy == "image" && scene.visual_prompt.present?
    end

    def user_prompt(scenes)
      scenes.map { |scene|
        meta = scene.metadata || {}
        <<~SCENE.strip
          --- #{scene.key} (#{scene.duration_seconds.to_f}s)
          purpose: #{scene.purpose}
          subject (keep identical): #{meta['subject']}
          environment (keep identical): #{meta['environment']}
          action: #{scene.action}
          mood: #{scene.mood}
          camera intent: #{scene.camera.to_json}
          visual_prompt: #{scene.visual_prompt}
          negative_prompt: #{scene.negative_prompt}
        SCENE
      }.join("\n\n").prepend("Visual style: #{@project.visual_style.tr('_', ' ')}\n\n")
    end

    def parse(text)
      json = text.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      data = JSON.parse(json)
      list = data["scenes"]
      raise Error, "shot plan JSON has no scenes array" unless list.is_a?(Array)

      list.to_h { |entry| [ entry["key"], Array(entry["shots"]).first(MAX_SHOTS) ] }
    rescue JSON::ParserError => e
      raise Error, "shot plan JSON did not parse: #{e.message}"
    end

    def replace_shots(scene, shots_data)
      shots_data = Array(shots_data)
      return [] if shots_data.empty?

      durations = normalized_durations(scene, shots_data)

      scene.transaction do
        scene.shots.destroy_all
        shots_data.each_with_index.map do |raw, i|
          key = "#{scene.key}_shot_#{i + 1}"
          direction = DirectionParser.new(project: @project, unit_key: key).parse(raw["direction"])

          scene.shots.create!(
            position: i + 1,
            key: key,
            duration_seconds: durations[i],
            shot_type: raw["shot_type"].presence || "static",
            # Task 4: prefer the Director's validated camera_motion; fall back
            # to the shot planner's own long-standing camera_movement field.
            camera_movement: direction[:camera_movement] || raw["camera_movement"].presence,
            framing: raw["framing"].presence,
            action: raw["action"],
            visual_type: scene.visual_type,
            content_type: scene.content_type,
            asset_strategy: scene.asset_strategy,
            visual_prompt: raw["visual_prompt"].presence || scene.visual_prompt,
            negative_prompt: raw["negative_prompt"].presence || scene.negative_prompt,
            motion: { "intensity" => direction[:intensity] }.compact,
            status: "pending",
            metadata: {
              direction_reason: direction[:direction_reason],
              overlay: direction[:overlay],
              direction_text: {
                "text_style" => direction[:text_style], "items" => direction[:items],
                "number" => direction[:number], "unit" => direction[:unit]
              }.compact.presence
            }.compact
          )
        end
      end
    end

    # Scale the model's shot durations to sum exactly to the scene duration.
    def normalized_durations(scene, shots_data)
      raw = shots_data.map { |s| [ s["duration_seconds"].to_f, 0.5 ].max }
      total = raw.sum
      target = scene.duration_seconds.to_f
      scaled = raw.map { |d| (d / total * target).round(2) }
      scaled[-1] = (target - scaled[0...-1].sum).round(2)
      scaled[-1] = 0.5 if scaled[-1] < 0.5
      scaled
    end
  end
end
