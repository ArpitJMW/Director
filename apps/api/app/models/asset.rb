class Asset < ApplicationRecord
  include HasPublicId
  has_public_id :ast

  ASSET_TYPES = %w[image video audio music logo caption_file thumbnail].freeze
  # spec §6, §27
  SOURCE_TYPES = %w[ai_generated user_provided licensed public_domain stock other].freeze

  belongs_to :project
  belongs_to :scene, optional: true
  belongs_to :ai_generation, optional: true

  has_many :selected_by_scenes, class_name: "Scene", foreign_key: :selected_asset_id, dependent: :nullify, inverse_of: :selected_asset

  validates :asset_type, inclusion: { in: ASSET_TYPES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }

  before_validation :sync_ai_generated_flag

  scope :requiring_disclosure, -> { where(requires_disclosure: true) }
  scope :project_level, -> { where(scene_id: nil) }

  private

  def sync_ai_generated_flag
    self.ai_generated = true if source_type == "ai_generated"
  end
end
