class Scene < ApplicationRecord
  include HasPublicId
  has_public_id :scn

  # spec §23 — the Visual Director picks one of these per scene
  VISUAL_TYPES = %w[
    image generated_video animated_diagram chart timeline map
    quote_card text_animation screen_recording split_screen
  ].freeze
  # spec §25
  ANIMATIONS = %w[ken_burns pan scale text_reveal none].freeze
  # Phase 1 Task 4 — Director Direction Layer. "fade" is kept only because
  # every scene planned before this task already has it stored as the
  # pre-Task-4 default; the renderer treats it as a no-op (a hard cut), same
  # as "cut" — "crossfade" is the new value that actually enables a dissolve.
  # Mirrored in packages/video-schema's TRANSITIONS.
  TRANSITIONS = %w[cut fade crossfade fade_from_black slide wipe zoom].freeze
  STATUSES = %w[pending generating_prompt generating_asset ready failed].freeze

  # spec §5/§6 — how a scene picks its visual medium
  ASSET_STRATEGIES = %w[image image_to_video animation chart text screen user_asset mixed].freeze

  # Phase 1 Task 4/4.2 Part B: none of these five have a real executor —
  # Media::ProductionDispatcher only ever routes to an image or a text unit
  # (see the Task 4 report's Step 0). "map" and "split_screen" were excluded
  # in Task 4; Task 4.2's real check caught the planner choosing
  # "generated_video" too (silently fell back to image) — "animated_diagram"
  # and "screen_recording" have the exact same problem and were never
  # actually instructed by any prompt, so they're excluded here for the same
  # reason rather than waiting to hit the same bug separately. All five
  # remain in VISUAL_TYPES/valid so old rows still load.
  PLANNABLE_VISUAL_TYPES = (VISUAL_TYPES - %w[map split_screen generated_video animated_diagram screen_recording]).freeze

  # Phase 1 Task 4 — the Director's render-capability catalog. Mirrored in
  # packages/video-schema (CAMERA_MOTIONS / CAMERA_INTENSITIES / OVERLAY_TYPES
  # / TEXT_STYLES); kept here too since Ruby can't import the TS source, and
  # this is what Ai::ScenePlannerService / Ai::ShotPlanner validate the LLM's
  # "direction" object against before ever writing it.
  CAMERA_MOTIONS = %w[
    static slow_push_in push_in pull_out pan_left pan_right tilt_up drift dramatic_zoom
  ].freeze
  CAMERA_INTENSITIES = %w[low medium high].freeze
  OVERLAY_TYPES = %w[none keyword_highlight lower_third stat_callout title_card].freeze
  TEXT_STYLES = %w[stagger_reveal punch_in big_number quote list_reveal timeline].freeze

  belongs_to :project
  belongs_to :script, optional: true
  belongs_to :selected_asset, class_name: "Asset", optional: true

  # Tear-down order matters: shots reference assets via selected_asset_id, and
  # voice_generations reference an audio asset — both must go before assets.
  has_many :shots, -> { order(:position) }, dependent: :destroy, inverse_of: :scene
  has_many :voice_generations, -> { order(:created_at) }, dependent: :destroy, inverse_of: :scene
  has_many :assets, dependent: :destroy
  has_many :ai_generations, dependent: :nullify
  has_many :generation_logs, dependent: :nullify

  def current_voice_generation
    voice_generations.last
  end

  # Phase 1 Task 3: computed, not stored (no migration) — true when the
  # asset/audio this scene currently has no longer matches what it's
  # supposed to be (asset_strategy/visual_prompt/etc changed, or it was never
  # generated at all). "ready" is the one status that means "the current
  # asset is correct as of the last save"; anything else needs the pipeline
  # to (re)generate it.
  def needs_regeneration?
    status != "ready"
  end

  # Phase 1 Task 3: true when a direction-only edit (camera/transition/
  # overlay/text_style — never touches `status`) landed after the project's
  # last completed render, so the existing asset is still valid but the
  # video on screen doesn't reflect it yet. False when nothing has ever
  # rendered — regeneration (above) is the more meaningful signal then.
  def needs_rerender?
    last_rendered_at = project.video_renders.where(status: "completed").maximum(:finished_at)
    return false if last_rendered_at.nil?

    updated_at > last_rendered_at
  end

  validates :key, presence: true, uniqueness: { scope: :project_id }
  validates :position, presence: true,
    numericality: { greater_than: 0 },
    uniqueness: { scope: :project_id }
  validates :duration_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 120 }
  validates :visual_type, inclusion: { in: VISUAL_TYPES }
  validates :animation, inclusion: { in: ANIMATIONS }
  validates :transition, inclusion: { in: TRANSITIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :asset_strategy, inclusion: { in: ASSET_STRATEGIES }
  validates :background_music_level,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  before_validation :assign_key_and_position, on: :create

  # The Scene JSON contract (spec §19 + planning-doc §6). Interchange shape shared
  # with the renderer (packages/video-schema). New direction fields and `shots`
  # are only emitted when set, so old consumers and old manifests are unaffected.
  def to_scene_json
    base = {
      id: key,
      duration: duration_seconds.to_f,
      narration: narration,
      visual_type: visual_type,
      visual_prompt: visual_prompt,
      asset_id: selected_asset&.public_id,
      caption: caption,
      animation: animation,
      transition: transition,
      background_music_level: background_music_level.to_f
    }

    direction = {
      purpose: purpose,
      content_type: content_type,
      action: action,
      camera: camera.presence,
      motion: motion.presence,
      mood: mood,
      asset_strategy: asset_strategy,
      negative_prompt: negative_prompt,
      # Set by whichever Media::ProductionDispatcher-routed service actually
      # produced this scene's visual (Phase 1 Task 2) — absent until then.
      production_method: metadata["production_method"],
      # Falls back to the Director's planned text_style/items (Task 4) before
      # Media::TextAnimationSpecService has actually built the full spec, so
      # the Task 3 UI has something real to preview, not an empty card.
      text_spec: metadata["text_spec"] || metadata["direction_text"],
      # Optional on-image decoration the Director chose (Phase 1 Task 4).
      overlay: metadata["overlay"],
      visual_reason: metadata["visual_reason"],
      direction_reason: metadata["direction_reason"]
    }.compact

    loaded_shots = shots.loaded? ? shots.to_a : shots.order(:position).to_a
    base[:shots] = loaded_shots.map(&:to_shot_json) if loaded_shots.any?

    base.merge(direction)
  end

  private

  def assign_key_and_position
    self.position ||= (project&.scenes&.maximum(:position) || 0) + 1
    self.key ||= format("scene_%02d", position)
  end
end
