class Script < ApplicationRecord
  include HasPublicId
  has_public_id :scr

  SOURCE_TYPES = %w[ai_generated user_provided ai_edited].freeze

  belongs_to :project
  belongs_to :ai_generation, optional: true
  has_many :scenes, dependent: :nullify
  has_many :voice_generations, dependent: :nullify

  validates :version, numericality: { greater_than: 0 }
  validates :source_type, inclusion: { in: SOURCE_TYPES }

  scope :current, -> { where(current: true) }

  before_validation :assign_version, on: :create
  before_save :demote_other_current_scripts,
    if: -> { current? && (new_record? || will_save_change_to_current?) }

  private

  # The column carries a DB default of 1; always compute the real next version
  # for new records.
  def assign_version
    self.version = (project.scripts.where.not(id: id).maximum(:version) || 0) + 1
  end

  # Keep a single current script per project (enforced by a partial unique index).
  def demote_other_current_scripts
    scope = project.scripts.where(current: true)
    scope = scope.where.not(id: id) if persisted?
    scope.update_all(current: false)
  end
end
