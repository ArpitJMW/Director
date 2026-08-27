class VoiceGeneration < ApplicationRecord
  include HasPublicId
  has_public_id :vox

  STATUSES = %w[pending running succeeded failed].freeze

  belongs_to :project
  belongs_to :scene, optional: true
  belongs_to :script, optional: true
  belongs_to :audio_asset, class_name: "Asset", optional: true
  belongs_to :ai_generation, optional: true

  validates :provider, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }
end
