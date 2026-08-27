class PreflightReport < ApplicationRecord
  include HasPublicId
  has_public_id :pfl

  STATUSES = %w[ready review_required].freeze
  DISCLOSURE = %w[required not_required review].freeze
  # spec §32
  CHECK_KEYS = %w[
    originality narrative_value repetition_risk asset_provenance reuse_risk
    copyright_license advertiser_suitability
  ].freeze
  CHECK_VERDICTS = %w[pass warn review].freeze

  belongs_to :project
  belongs_to :video_render, optional: true
  belongs_to :generated_by_generation, class_name: "AiGeneration", optional: true
  belongs_to :acknowledged_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :ai_disclosure, inclusion: { in: DISCLOSURE }

  scope :acknowledged, -> { where.not(acknowledged_at: nil) }

  def acknowledge!(user)
    update!(acknowledged_by: user, acknowledged_at: Time.current)
  end

  def ready?
    status == "ready"
  end
end
