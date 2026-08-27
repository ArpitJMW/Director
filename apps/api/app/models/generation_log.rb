class GenerationLog < ApplicationRecord
  LEVELS = %w[debug info warn error].freeze

  belongs_to :project
  belongs_to :generation_job, optional: true
  belongs_to :ai_generation, optional: true
  belongs_to :scene, optional: true

  validates :level, inclusion: { in: LEVELS }
  validates :message, presence: true

  # Append-only.
  before_update { raise ActiveRecord::ReadOnlyRecord, "generation_logs are append-only" }

  scope :errors, -> { where(level: "error") }
end
