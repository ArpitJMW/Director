class Shot < ApplicationRecord
  include HasPublicId
  has_public_id :sht

  # Smallest visual unit (spec §6/§7). Generated and rendered individually; a
  # scene plays its shots in sequence. Vocab is advisory — the planner picks
  # from it but unknown values are tolerated so the pipeline never hard-fails.
  SHOT_TYPES = %w[
    wide establishing medium close_up tracking push_in pull_out
    pan tilt top_down static screen chart
  ].freeze
  STATUSES = %w[pending generating_asset ready failed].freeze

  belongs_to :scene
  belongs_to :selected_asset, class_name: "Asset", optional: true
  has_one :project, through: :scene

  has_many :assets, dependent: :nullify
  has_many :ai_generations, dependent: :nullify

  scope :ordered, -> { order(:position) }

  validates :key, presence: true, uniqueness: { scope: :scene_id }
  validates :position, presence: true,
    numericality: { greater_than: 0 },
    uniqueness: { scope: :scene_id }
  validates :duration_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 120 }
  validates :status, inclusion: { in: STATUSES }
  validates :visual_type, inclusion: { in: Scene::VISUAL_TYPES }
  validates :asset_strategy, inclusion: { in: Scene::ASSET_STRATEGIES }

  before_validation :assign_key_and_position, on: :create

  # Render-side contract for one shot. Kept flat and camelCase-free; the renderer
  # schema (packages/video-schema) mirrors this.
  def to_shot_json
    {
      id: key,
      duration: duration_seconds.to_f,
      shot_type: shot_type,
      camera_movement: camera_movement,
      framing: framing,
      action: action,
      visual_type: visual_type,
      asset_id: selected_asset&.public_id,
      motion: motion.presence || {},
      # Set by whichever Media::ProductionDispatcher-routed service actually
      # produced this shot's visual (Phase 1 Task 2) — nil until then.
      production_method: metadata["production_method"],
      text_spec: metadata["text_spec"] || metadata["direction_text"],
      # Optional on-image decoration the Director chose (Phase 1 Task 4).
      overlay: metadata["overlay"],
      direction_reason: metadata["direction_reason"]
    }
  end

  private

  def assign_key_and_position
    self.position ||= (scene&.shots&.maximum(:position) || 0) + 1
    self.key ||= "#{scene&.key || 'scene'}_shot_#{position}"
  end
end
