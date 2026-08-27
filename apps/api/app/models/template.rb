class Template < ApplicationRecord
  include HasPublicId
  has_public_id :tpl

  STATUSES = %w[draft published archived].freeze

  belongs_to :owner, class_name: "User", optional: true # null => built-in
  belongs_to :latest_version, class_name: "TemplateVersion", optional: true
  belongs_to :preview_asset, class_name: "Asset", optional: true

  has_many :versions, -> { order(:version) }, class_name: "TemplateVersion", dependent: :destroy, inverse_of: :template
  has_many :projects, dependent: :nullify

  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9-]+\z/, message: "must be lowercase, digits and hyphens" }
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "published") }
  scope :built_in, -> { where(owner_id: nil) }

  def publish_version!(config:, changelog: nil)
    version = versions.create!(
      version: (versions.maximum(:version) || 0) + 1,
      config: config,
      changelog: changelog,
      published_at: Time.current
    )
    update!(latest_version: version, status: "published")
    version
  end
end
