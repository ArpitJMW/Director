class MusicTrack < ApplicationRecord
  include HasPublicId
  has_public_id :mus

  SOURCE_TYPES = %w[ai_generated licensed public_domain stock].freeze

  belongs_to :project, optional: true # null => shared library track
  belongs_to :asset, optional: true

  validates :source_type, inclusion: { in: SOURCE_TYPES }

  scope :library, -> { where(project_id: nil) }
end
