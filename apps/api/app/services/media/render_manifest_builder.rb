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
      scenes = @project.scenes.order(:position).to_a
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
        music: nil
      }
    end

    private

    def template_config
      @project.template_version&.config ||
        @project.template&.latest_version&.config ||
        {}
    end

    def scene_entry(scene)
      voice = scene.current_voice_generation
      scene.to_scene_json.merge(
        asset_id: scene.selected_asset&.public_id,
        narration_audio_url: absolute(voice&.audio_asset&.signed_url(expires_in: URL_TTL)),
        alignment: voice&.alignment,
        captions: voice&.captions || []
      )
    end

    def asset_entries(scenes)
      scenes.filter_map(&:selected_asset).uniq.map do |asset|
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
