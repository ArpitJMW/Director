class VideoRender < ApplicationRecord
  include HasPublicId
  include AASM

  has_public_id :rnd

  belongs_to :project
  belongs_to :template_version, optional: true
  belongs_to :output_asset, class_name: "Asset", optional: true
  has_many :preflight_reports, dependent: :nullify

  validates :version, numericality: { greater_than: 0 }
  validates :progress, numericality: { in: 0..100 }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }

  before_create :assign_version

  aasm column: :status, no_direct_assignment: true do
    state :queued, initial: true
    state :rendering
    state :uploading
    state :completed
    state :failed
    state :cancelled

    event :start do
      transitions from: :queued, to: :rendering
      after { update_column(:started_at, Time.current) }
    end

    event :start_upload do
      transitions from: :rendering, to: :uploading
    end

    event :complete do
      transitions from: :uploading, to: :completed
      after do
        update_columns(finished_at: Time.current, progress: 100)
      end
    end

    event :mark_failed do
      transitions from: [ :queued, :rendering, :uploading ], to: :failed
      after { update_column(:finished_at, Time.current) }
    end

    event :cancel do
      transitions from: [ :queued, :rendering, :uploading ], to: :cancelled
    end

    event :requeue do
      transitions from: [ :failed, :cancelled ], to: :queued
    end
  end

  private

  # Task 4.1 real-run bug fix: the `version` column has a DB-level default of
  # 1 (so a bare `INSERT` without the column still satisfies `NOT NULL`) —
  # meaning every new, unsaved record already has `version == 1` the instant
  # it's built, before this callback ever runs. `||=` therefore ALWAYS
  # short-circuited on that default and never computed anything, so this
  # never actually assigned past 1 — invisible until a project's SECOND
  # render collided with the first on the unique (project_id, version)
  # index. No caller ever passes an explicit version (grepped the app +
  # specs), so there's nothing meaningful for `||=` to have been guarding.
  def assign_version
    self.version = (project.video_renders.maximum(:version) || 0) + 1
  end
end
