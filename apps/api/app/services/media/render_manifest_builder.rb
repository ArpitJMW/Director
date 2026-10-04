module Media
  # Builds the render manifest (spec §20 step 14): a fully-resolved storyboard +
  # template config + audio that the Remotion renderer consumes. Mirrors
  # @clipify/video-schema RenderManifestSchema.
  class RenderManifestBuilder
    Error = Class.new(StandardError)

    # Signed URLs must outlive the render.
    URL_TTL = 6 * 60 * 60

    DIMENSIONS = {
      "16:9" => [ 1920, 1080 ],
      "9:16" => [ 1080, 1920 ],
      "1:1" => [ 1080, 1080 ]
    }.freeze

    def initialize(project:, video_render:, asset_base_url: nil)
      @project = project
      @render = video_render
      @base = (asset_base_url || ENV.fetch("RENDER_ASSET_BASE_URL", "http://localhost:3000")).chomp("/")
    end

    def call
      scenes = @project.scenes.order(:position)
        .includes(:selected_asset, shots: :selected_asset).to_a
      raise Error, "project has no scenes" if scenes.empty?

      width, height = DIMENSIONS.fetch(@project.aspect_ratio, DIMENSIONS["16:9"])

      {
        render_id: @render.public_id,
        project_id: @project.public_id,
        width: width,
        height: height,
        fps: @render.fps || 30,
        template: template_config,
        scenes: scenes.map { |scene| scene_entry(scene) },
        assets: asset_entries(scenes),
        look: look_entry,
        music: nil
      }
    end

    private

    # Task 6.2 Part 2: only the grade reaches the renderer; the rest of the look
    # steers image generation, not the video.
    def look_entry
      look = (@project.settings || {})["look"]
      return nil unless look.is_a?(Hash)

      { grade: look["grade"] == "film" ? "film" : "clean" }
    end

    def template_config
      @project.template_version&.config ||
        @project.template&.latest_version&.config ||
        {}
    end

    def scene_entry(scene)
      voice = scene.current_voice_generation
      guard_audio_fits_slot!(scene, voice)
      json = scene.to_scene_json.merge(
        asset_id: scene.selected_asset&.public_id,
        narration_audio_url: absolute(voice&.audio_asset&.signed_url(expires_in: URL_TTL)),
        alignment: voice&.alignment,
        captions: voice&.captions || []
      )
      paced = paced_shots(scene, json)
      paced ? json.merge(shots: paced) : json
    end

    # Task 5C: after narration has set the real duration, no image unit may hold
    # longer than VisualPacing::MAX_UNIT_SECONDS. Over-long units become sub-shots
    # reusing the same image (no provider call). Returns nil when nothing changes,
    # so scenes that were already paced keep their stored shape exactly.
    def paced_shots(scene, json)
      return nil unless scene.asset_strategy == "image" && json[:production_method] != "text"

      units = json[:shots].presence || [ scene_as_unit(scene, json) ]
      paced = VisualPacing.subdivide(units)
      return nil if paced.map { |u| u[:duration] } == units.map { |u| u[:duration] }

      paced
    end

    def scene_as_unit(scene, json)
      {
        id: scene.key,
        duration: scene.duration_seconds.to_f,
        shot_type: "static",
        camera_movement: scene.camera.is_a?(Hash) ? scene.camera["movement"] : nil,
        framing: nil,
        action: scene.action,
        visual_type: scene.visual_type,
        asset_id: json[:asset_id],
        motion: json[:motion] || {},
        production_method: json[:production_method],
        text_spec: json[:text_spec],
        overlay: json[:overlay],
        direction_reason: json[:direction_reason]
      }
    end

    # Phase 1 Task 2.6: Media::SceneDurationService reconciles scene.duration_seconds
    # to the real measured narration length right after voice generation, so this
    # should never actually fire — kept as a guard so a stale/regenerated scene
    # that somehow skipped reconciliation is caught (audio would otherwise be cut
    # off mid-sentence by the renderer's per-scene Sequence) rather than silently
    # shipping a truncated render.
    def guard_audio_fits_slot!(scene, voice)
      return unless voice&.duration_seconds

      overflow = voice.duration_seconds.to_f - scene.duration_seconds.to_f
      return if overflow <= 0.05

      GenerationLog.create!(
        project: @project, scene: scene, level: "warn", stage: "render",
        message: "#{scene.key}: narration audio (#{voice.duration_seconds.to_f.round(2)}s) exceeds " \
                  "its slot (#{scene.duration_seconds.to_f.round(2)}s) — should not happen after duration reconciliation"
      )
    end

    def asset_entries(scenes)
      scene_assets = scenes.filter_map(&:selected_asset)
      shot_assets = scenes.flat_map(&:shots).filter_map(&:selected_asset)
      (scene_assets + shot_assets).uniq.map do |asset|
        {
          id: asset.public_id,
          type: asset.asset_type,
          url: absolute(asset.signed_url(expires_in: URL_TTL)),
          width: asset.width,
          height: asset.height,
          duration: asset.duration_seconds&.to_f
        }
      end
    end

    def absolute(url)
      return nil if url.blank?
      return url if url.start_with?("http")

      "#{@base}#{url}"
    end
  end
end
