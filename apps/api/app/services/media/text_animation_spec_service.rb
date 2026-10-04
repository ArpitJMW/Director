module Media
  # Builds a structured on-screen text spec for asset_strategy "text" beats
  # (planning-doc §14 kinetic typography). No provider call, no Asset row — the
  # spec is stored in the unit's own metadata jsonb. Mirrors
  # Media::ImageGenerationService's public interface (#generatable?, #call) so
  # Media::ProductionDispatcher can hand either service to AssetsJob /
  # SceneAssetJob without either job knowing which one it got.
  class TextAnimationSpecService
    MAX_WORDS_PER_LINE = 5
    MAX_LINES = 4
    STOPWORDS = %w[
      the a an of to in on at by for and or but is are was were be been with
      this that it its as from into over under out up down not no so than
    ].freeze

    # Phase 1 Task 4.2 Part C: list_reveal/timeline read one item per line at
    # a large font — an unbounded list or an unbounded item string is how a
    # beat overflows the 1080p frame. The catalog's own "2-4 items"/"3-5
    # steps" guidance is a planning-time suggestion the LLM can ignore; these
    # are the hard ceiling enforced regardless of what actually arrives here.
    MAX_ITEMS = 5
    MAX_ITEM_CHARS = 44
    MAX_UNIT_CHARS = 12

    # @param scene [Scene] the scene (or the shot's scene)
    # @param shot [Shot, nil] build for this specific shot
    def initialize(scene: nil, shot: nil)
      @shot = shot
      @scene = scene || shot&.scene
      raise ArgumentError, "need a scene or a shot" if @scene.nil?
    end

    def generatable?
      @scene.narration.present? || @scene.caption.present?
    end

    def call
      return nil unless generatable?

      target = @shot || @scene
      target.update!(status: "generating_asset", failure_reason: nil)

      spec = build_spec
      target.update!(metadata: target.metadata.merge(
        "production_method" => "text", "text_spec" => spec
      ))
      target.update!(status: "ready")

      attach
      spec
    rescue => e
      (@shot || @scene).update(status: "failed", failure_reason: e.message)
      raise
    end

    private

    # Lines are what actually appears on screen — the planner already wrote a
    # short (<=6 word) caption for exactly this purpose, so prefer it; fall
    # back to chunking the narration when a scene has no caption.
    def lines
      text = @scene.caption.presence || @scene.narration.to_s
      chunks = text.split(/\s+/).each_slice(MAX_WORDS_PER_LINE).map { |w| w.join(" ") }
      chunks.first(MAX_LINES).presence || [ text ]
    end

    # Keywords come from the full narration (broader context than the caption
    # alone), stripped of stopwords and short filler.
    def keywords
      @scene.narration.to_s.downcase.scan(/[a-z']+/)
        .reject { |w| STOPWORDS.include?(w) || w.length < 4 }
        .uniq.first(6)
    end

    # Only emphasize keywords that actually appear in a displayed line —
    # highlighting a word the viewer never sees would be meaningless.
    def emphasis
      shown = lines.join(" ").downcase
      keywords.select { |w| shown.include?(w) }.first(2)
    end

    def build_spec
      {
        "lines" => lines,
        "keywords" => keywords,
        "emphasis" => emphasis,
        "style" => @scene.content_type.presence || "kinetic_typography",
        "animation_style" => @scene.animation.presence || "text_reveal",
        "duration" => (@shot&.duration_seconds || @scene.duration_seconds).to_f
      }.merge(direction_text)
    end

    # The Director's text_style/items/number/unit choice (Phase 1 Task 4),
    # set by Ai::ScenePlannerService / Ai::ShotPlanner on this exact unit —
    # never the scene's when building for a shot, each unit picked its own.
    # Absent (older plans, or a unit the Director left as plain
    # stagger_reveal) simply contributes nothing, so `build_spec` above falls
    # back to the pre-Task-4 shape. Task 4.2 Part C: items/unit are re-capped
    # here regardless of what the planner already enforced (Ai::
    # DirectionParser caps at 6 items/44 chars is a planning-time concern;
    # this is the last line of defense right before the renderer, in case a
    # spec was ever written some other way).
    def direction_text
      raw = (@shot || @scene).metadata["direction_text"]
      return {} unless raw.is_a?(Hash)

      sanitized = raw.dup
      if sanitized["items"].is_a?(Array)
        sanitized["items"] = sanitized["items"].first(MAX_ITEMS).map { |i| truncate_item(i) }
      end
      sanitized["unit"] = truncate_item(sanitized["unit"], MAX_UNIT_CHARS) if sanitized["unit"].present?
      sanitized
    end

    def truncate_item(text, limit = MAX_ITEM_CHARS)
      text = text.to_s
      return text if text.length <= limit

      "#{text[0, limit - 1].rstrip}…"
    end

    # Mirrors Media::ImageGenerationService#attach's status bookkeeping, minus
    # selected_asset (there is no Asset for a text unit).
    def attach
      return @scene.update!(status: "ready") unless @shot

      @scene.update!(status: "ready") if @scene.shots.where.not(status: "ready").none?
    end
  end
end
