class AiGeneration < ApplicationRecord
  include HasPublicId
  has_public_id :gen

  KINDS = %w[
    research script scene_plan visual_prompt image video voice caption
    music fact_check quality_check preflight
  ].freeze
  PROVIDER_KINDS = %w[llm image voice music video].freeze
  STATUSES = %w[pending running succeeded failed].freeze

  belongs_to :project, optional: true
  belongs_to :scene, optional: true

  has_many :assets, dependent: :nullify
  has_many :scripts, dependent: :nullify
  has_many :voice_generations, dependent: :nullify
  has_many :generation_logs, dependent: :nullify

  validates :kind, inclusion: { in: KINDS }
  validates :provider_kind, inclusion: { in: PROVIDER_KINDS }
  validates :provider, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }

  scope :succeeded, -> { where(status: "succeeded") }

  def duration_ms
    return latency_ms if latency_ms
    return unless started_at && finished_at

    ((finished_at - started_at) * 1000).round
  end
end
