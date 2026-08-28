module Media
  # Generates one image for a scene from its visual_prompt and attaches it as the
  # scene's selected asset (spec §14 media/image_generation_service, §20 step 10).
  class ImageGenerationService
    Error = Class.new(StandardError)

    # visual_types this service produces a generated still for (used as the
    # scene background, animated by the renderer). text_animation / chart /
    # timeline / quote_card / screen_recording get a text card instead.
    IMAGE_TYPES = %w[image split_screen generated_video animated_diagram map].freeze

    def initialize(scene:, provider: Providers.image)
      @scene = scene
      @project = scene.project
      @provider = provider
    end

    def generatable?
      IMAGE_TYPES.include?(@scene.visual_type) && @scene.visual_prompt.present?
    end

    def call
      return nil unless generatable?

      @scene.update!(status: "generating_asset", failure_reason: nil)

      generation = nil
      result = AiGeneration.track!(
        project: @project, scene: @scene, kind: "image", provider_kind: "image",
        provider: @provider.name, model: @provider.default_model,
        request: { prompt: @scene.visual_prompt, aspect_ratio: @project.aspect_ratio }
      ) do |gen|
        generation = gen
        @provider.generate(prompt: @scene.visual_prompt, aspect_ratio: @project.aspect_ratio)
      end

      asset = Asset.store!(
        project: @project, scene: @scene, asset_type: "image",
        io: result.io, content_type: result.content_type,
        source_type: "ai_generated", provider: result.provider, model: result.model,
        prompt: @scene.visual_prompt, provider_request_id: result.provider_request_id,
        cost_usd: result.cost_usd, ai_generation: generation, realistic: false
      )

      @scene.update!(selected_asset: asset, status: "ready")
      asset
    rescue => e
      @scene.update(status: "failed", failure_reason: e.message)
      raise
    end
  end
end
