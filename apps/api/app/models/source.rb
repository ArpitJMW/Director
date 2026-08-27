class Source < ApplicationRecord
  include HasPublicId
  has_public_id :src

  RELIABILITIES = %w[unknown low medium high].freeze
  PROVIDERS = %w[user research_engine].freeze

  belongs_to :project

  validates :reliability, inclusion: { in: RELIABILITIES }
  validates :provided_by, inclusion: { in: PROVIDERS }
  validates :url, length: { maximum: 2000 }, allow_blank: true
end
