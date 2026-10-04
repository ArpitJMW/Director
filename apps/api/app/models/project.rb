class Project < ApplicationRecord
  include HasPublicId
  include AASM

  has_public_id :proj

  FORMATS = %w[youtube_long youtube_short reel].freeze
  ASPECT_RATIOS = %w[16:9 9:16 1:1].freeze
  VISUAL_STYLES = %w[cinematic photorealistic wildlife_documentary documentary 3d_animation illustration anime watercolor].freeze

  # Lifecycle stages (spec §18). `failed` and `cancelled` are terminal-ish;
  # `completed` is terminal.
  WORKING_STATES = %i[
    researching script_generating storyboarding generating_assets
    generating_voice generating_captions rendering quality_check
  ].freeze

  belongs_to :user
  belongs_to :template, optional: true
  belongs_to :template_version, optional: true

  has_many :scripts, dependent: :destroy
  has_many :sources, dependent: :destroy
  has_many :scenes, -> { order(:position) }, dependent: :destroy, inverse_of: :project
  has_many :assets, dependent: :destroy
  has_many :voice_generations, dependent: :destroy
  has_many :music_tracks, dependent: :nullify
  has_many :video_renders, dependent: :destroy
  has_many :ai_generations, dependent: :nullify
  has_many :generation_jobs, dependent: :destroy
  has_many :generation_logs, dependent: :delete_all
  has_many :preflight_reports, dependent: :destroy

  has_one :current_script, -> { where(current: true) }, class_name: "Script", inverse_of: :project

  validates :title, presence: true, length: { maximum: 200 }
  validates :format, inclusion: { in: FORMATS }
  validates :aspect_ratio, inclusion: { in: ASPECT_RATIOS }
  validates :visual_style, inclusion: { in: VISUAL_STYLES }
  validates :target_duration_seconds,
    numericality: { greater_than_or_equal_to: 15, less_than_or_equal_to: 1800 }

  aasm column: :status, no_direct_assignment: true do
    state :draft, initial: true
    state :researching
    state :script_generating
    state :storyboarding
    state :generating_assets
    state :generating_voice
    state :generating_captions
    state :rendering
    state :quality_check
    state :completed
    state :failed
    state :cancelled

    event :start_research do
      transitions from: :draft, to: :researching
    end

    # start_* events also accept :failed so a stage can be retried in place; the
    # controller still gates on whether the stage's real prerequisite exists.
    event :start_script do
      before { self.failure_reason = nil }
      transitions from: [ :draft, :researching, :failed ], to: :script_generating
    end

    event :start_storyboard do
      before { self.failure_reason = nil }
      transitions from: [ :draft, :script_generating, :storyboarding, :failed ], to: :storyboarding
    end

    event :start_assets do
      before { self.failure_reason = nil }
      transitions from: [ :draft, :script_generating, :storyboarding, :generating_assets, :failed ], to: :generating_assets
    end

    event :start_voice do
      before { self.failure_reason = nil }
      transitions from: [ :draft, :storyboarding, :generating_assets, :generating_voice, :failed ], to: :generating_voice
    end

    event :start_captions do
      transitions from: [ :generating_voice, :failed ], to: :generating_captions
    end

    event :start_render do
      before { self.failure_reason = nil }
      transitions from: [ :draft, :generating_assets, :generating_voice, :generating_captions, :rendering, :failed ], to: :rendering
    end

    event :start_quality_check do
      transitions from: :rendering, to: :quality_check
    end

    event :complete do
      transitions from: [ :rendering, :quality_check ], to: :completed
      after { update_column(:completed_at, Time.current) }
    end

    event :mark_failed do
      before { self.failed_from_status = status }
      transitions from: WORKING_STATES, to: :failed
    end

    event :cancel do
      transitions from: [ :draft, *WORKING_STATES, :failed, :completed ], to: :cancelled
      after { update_column(:cancelled_at, Time.current) }
    end

    # Resume a failed project from the stage that failed (spec §28).
    event :resume do
      transitions from: :failed, to: :draft, if: :failed_from_draft?
      transitions from: :failed, to: :researching, if: -> { failed_from?(:researching) }
      transitions from: :failed, to: :script_generating, if: -> { failed_from?(:script_generating) }
      transitions from: :failed, to: :storyboarding, if: -> { failed_from?(:storyboarding) }
      transitions from: :failed, to: :generating_assets, if: -> { failed_from?(:generating_assets) }
      transitions from: :failed, to: :generating_voice, if: -> { failed_from?(:generating_voice) }
      transitions from: :failed, to: :generating_captions, if: -> { failed_from?(:generating_captions) }
      transitions from: :failed, to: :rendering, if: -> { failed_from?(:rendering) }
      transitions from: :failed, to: :quality_check, if: -> { failed_from?(:quality_check) }
      after { update_column(:failed_from_status, nil) }
    end

    event :reset_to_draft do
      transitions from: [ :failed, :cancelled, :completed ], to: :draft
    end
  end

  def failed_from?(state)
    failed_from_status.to_s == state.to_s
  end

  def failed_from_draft?
    failed_from_status.blank? || failed_from?(:draft)
  end
end
