module Media
  # Routes a production unit (a Shot, or a Scene when it has no shots) to the
  # service that actually executes its asset_strategy (Phase 1 Task 2 —
  # "Unified Production Engine"). Returns a service object exposing the same
  # interface Media::ImageGenerationService always has (#generatable?, #call),
  # so AssetsJob / SceneAssetJob drive whichever one they get identically —
  # neither job needs to know which production method was chosen.
  #
  # A Shot has its own asset_strategy column (defaulted from its parent scene
  # at creation, see Ai::ShotPlanner#replace_shots) so a future per-shot
  # override needs no interface change here — .for already reads whichever
  # unit (shot or scene) it was handed.
  module ProductionDispatcher
    module_function

    # asset_strategy => the method that currently executes it. Anything not
    # listed here has no executor yet (planning-doc's image_to_video, animation,
    # chart, screen, user_asset, mixed) and is routed to "image" instead, with
    # a GenerationLog entry recording why — never a silent fallback.
    EXECUTORS = { "image" => :image, "text" => :text }.freeze

    def for(scene: nil, shot: nil)
      unit = shot || scene
      raise ArgumentError, "need a scene or a shot" if unit.nil?

      strategy = unit.asset_strategy.presence || "image"
      method = EXECUTORS[strategy]

      unless method
        log_fallback(unit, strategy)
        method = :image
      end

      build(method, scene: scene, shot: shot)
    end

    def build(method, scene:, shot:)
      case method
      when :text then TextAnimationSpecService.new(scene: scene, shot: shot)
      else ImageGenerationService.new(scene: scene, shot: shot)
      end
    end
    private_class_method :build

    def log_fallback(unit, strategy)
      scene = unit.is_a?(Shot) ? unit.scene : unit
      GenerationLog.create!(
        project: scene.project, scene: scene, level: "warn", stage: "assets",
        message: "asset_strategy #{strategy.inspect} on #{unit.key} has no executor yet — falling back to image"
      )
    end
    private_class_method :log_fallback
  end
end
