module Media
  # Generates one image — for a shot when the scene has shots, otherwise for the
  # scene as a whole — and attaches it as the selected asset (planning-doc §7,
  # spec §20 step 10). The scene's selected_asset mirrors its first shot so the
  # storyboard UI keeps working unchanged.
  class ImageGenerationService
    Error = Class.new(StandardError)

    # Kept for Policy::ProvenanceChecker, which classifies scenes as
    # "expected to have a generated visual" independent of who generates it.
    # NOT used by #generatable? below (Phase 1 Task 2.3) — asset_strategy is
    # the production decision now; visual_type is only a conceptual label. A
    # scene can be visual_type "chart"/"timeline"/etc with asset_strategy
    # "image" (nothing else can produce it yet) and must still get an image.
    IMAGE_TYPES = %w[image split_screen generated_video animated_diagram map].freeze

    # @param scene [Scene] the scene (or the shot's scene)
    # @param shot [Shot, nil] generate for this specific shot
    def initialize(scene: nil, shot: nil, provider: Providers.image, brief_override: nil, setting_first: false,
                   compiled_prompt: nil)
      @shot = shot
      @compiled_prompt = compiled_prompt
      @brief_override = brief_override
      @setting_first = setting_first
      @scene = scene || shot&.scene
      @project = @scene&.project
      @provider = provider
      raise ArgumentError, "need a scene or a shot" if @scene.nil?
    end

    # True exactly when Media::ProductionDispatcher would route this unit
    # here: its own asset_strategy (falling back to the scene's) is "image"
    # and it has something to generate from. Trusts the caller's routing
    # decision rather than re-deriving it from visual_type.
    def generatable?
      unit_asset_strategy == "image" &&
        (@shot&.visual_prompt.presence || @scene.visual_prompt).present?
    end

    def call
      return nil unless generatable?

      target = @shot || @scene
      target.update!(status: "generating_asset", failure_reason: nil)

      built = ImagePromptBuilder.new(scene: @scene, shot: @shot, project: @project,
                                     brief_override: @brief_override, setting_first: @setting_first,
                                     compiled_prompt: @compiled_prompt).call

      generation = nil
      result = AiGeneration.track!(
        project: @project, scene: @scene, shot: @shot, kind: "image", provider_kind: "image",
        provider: @provider.name, model: @provider.default_model,
        request: built.merge(aspect_ratio: @project.aspect_ratio)
      ) do |gen|
        generation = gen
        @provider.generate(
          prompt: built[:prompt], negative_prompt: built[:negative_prompt],
          seed: built[:seed], aspect_ratio: @project.aspect_ratio
        )
      end

      bytes = cleaned_bytes(result)
      asset = Asset.store!(
        project: @project, scene: @scene, shot: @shot, asset_type: "image",
        io: StringIO.new(bytes), content_type: result.content_type,
        source_type: "ai_generated", provider: result.provider, model: result.model,
        prompt: built[:prompt], provider_request_id: result.provider_request_id,
        cost_usd: result.cost_usd, ai_generation: generation, realistic: false
      )

      attach(asset)
      asset
    rescue => e
      (@shot || @scene).update(status: "failed", failure_reason: e.message)
      raise
    end

    private

    def unit_asset_strategy
      (@shot || @scene).asset_strategy.presence || "image"
    end

    # Task 5C: a bad crop must never cost the image itself, so a failure keeps
    # the provider's original bytes and leaves a warning in the log.
    def cleaned_bytes(result)
      LetterboxCropper.new(aspect_ratio: @project.aspect_ratio)
        .call(bytes: result.bytes, content_type: result.content_type).bytes
    rescue LetterboxCropper::Error => e
      GenerationLog.create!(
        project: @project, scene: @scene, level: "warn", stage: "assets",
        message: "#{(@shot || @scene).try(:key)}: letterbox crop skipped — #{e.message.to_s.truncate(200)}"
      )
      result.bytes
    end

    def attach(asset)
      if @shot
        @shot.update!(selected_asset: asset, status: "ready")
        # keep the scene thumbnail pointing at its first shot's image
        first_shot = @scene.shots.order(:position).first
        @scene.update!(selected_asset: asset) if first_shot&.id == @shot.id || @scene.selected_asset.nil?
        @scene.update!(status: "ready") if @scene.shots.where.not(status: "ready").none?
      else
        @scene.update!(selected_asset: asset, status: "ready")
      end
    end
  end
end
