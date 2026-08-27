class GenerationJob < ApplicationRecord
  include HasPublicId
  include AASM

  has_public_id :job

  # Pipeline stages (spec §20)
  STAGES = %w[
    validate research collect_sources story_angle script fact_check storyboard
    visual_direction prompts assets voice narration captions music manifest render
    quality_check preflight finalize
  ].freeze

  belongs_to :project
  belongs_to :scene, optional: true
  belongs_to :parent_job, class_name: "GenerationJob", optional: true
  has_many :child_jobs, class_name: "GenerationJob", foreign_key: :parent_job_id, dependent: :nullify, inverse_of: :parent_job
  has_many :generation_logs, dependent: :nullify

  validates :stage, inclusion: { in: STAGES }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :attempts, :max_attempts, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_idempotency_key, on: :create

  ACTIVE_STATUSES = %w[pending queued running retrying].freeze
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :recent, -> { order(created_at: :desc) }

  aasm column: :status, no_direct_assignment: true do
    state :pending, initial: true
    state :queued
    state :running
    state :succeeded
    state :failed
    state :cancelled
    state :retrying

    event :enqueue do
      transitions from: [ :pending, :retrying ], to: :queued
      after { update_column(:scheduled_at, Time.current) }
    end

    event :start do
      transitions from: [ :queued, :pending, :retrying, :running ], to: :running
      after { increment_attempt! }
    end

    event :succeed do
      transitions from: :running, to: :succeeded
      after { update_column(:finished_at, Time.current) }
    end

    event :retry_later do
      transitions from: [ :running, :failed ], to: :retrying, if: :attempts_remaining?
    end

    event :mark_failed do
      transitions from: [ :queued, :running, :retrying ], to: :failed
      after { update_column(:finished_at, Time.current) }
    end

    event :cancel do
      transitions from: [ :pending, :queued, :running, :retrying ], to: :cancelled
    end
  end

  def attempts_remaining?
    attempts < max_attempts
  end

  private

  def increment_attempt!
    update_column(:attempts, attempts + 1)
    update_column(:started_at, Time.current)
  end

  def assign_idempotency_key
    self.idempotency_key ||= "#{project_id}:#{stage}:#{scene_id || 0}:#{SecureRandom.hex(6)}"
  end
end
