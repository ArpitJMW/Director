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
  TRANSITIONS = %w[fade slide zoom cut].freeze
  STATUSES = %w[pending generating_prompt generating_asset ready failed].freeze

  belongs_to :project
  belongs_to :script, optional: true
  belongs_to :selected_asset, class_name: "Asset", optional: true

  # voice_generations before assets: a vg references an audio asset, so it must
  # be torn down first.
  has_many :voice_generations, -> { order(:created_at) }, dependent: :destroy, inverse_of: :scene
  has_many :assets, dependent: :destroy
  has_many :ai_generations, dependent: :nullify
  has_many :generation_logs, dependent: :nullify

  def current_voice_generation
    voice_generations.last
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
  validates :background_music_level,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  before_validation :assign_key_and_position, on: :create

  # The Scene JSON contract (spec §19). This is the interchange shape shared
  # with the renderer (packages/video-schema).
  def to_scene_json
    {
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
  end

  private

  def assign_key_and_position
    self.position ||= (project&.scenes&.maximum(:position) || 0) + 1
    self.key ||= format("scene_%02d", position)
  end
end
