class TemplateVersion < ApplicationRecord
  include HasPublicId
  has_public_id :tplv

  # Keys expected in `config` (spec §24)
  CONFIG_SECTIONS = %w[
    typography colors caption_rules animation_rules transition_rules
    audio_rules scene_presets thumbnail_style
  ].freeze

  belongs_to :template
  has_many :projects, dependent: :nullify
  has_many :video_renders, dependent: :nullify

  validates :version, numericality: { greater_than: 0 }, uniqueness: { scope: :template_id }

  def published?
    published_at.present?
  end
end
