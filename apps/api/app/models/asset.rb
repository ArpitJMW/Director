class Asset < ApplicationRecord
  include HasPublicId
  has_public_id :ast

  ASSET_TYPES = %w[image video audio music logo caption_file thumbnail].freeze
  # spec §6, §27
  SOURCE_TYPES = %w[ai_generated user_provided licensed public_domain stock other].freeze

  belongs_to :project
  belongs_to :scene, optional: true
  belongs_to :shot, optional: true
  belongs_to :ai_generation, optional: true

  has_many :selected_by_scenes, class_name: "Scene", foreign_key: :selected_asset_id, dependent: :nullify, inverse_of: :selected_asset
  has_many :selected_by_shots, class_name: "Shot", foreign_key: :selected_asset_id, dependent: :nullify, inverse_of: :selected_asset

  validates :asset_type, inclusion: { in: ASSET_TYPES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }

  before_validation :sync_ai_generated_flag
  after_destroy_commit :purge_storage_object

  scope :requiring_disclosure, -> { where(requires_disclosure: true) }
  scope :project_level, -> { where(scene_id: nil) }

  EXTENSIONS = {
    "image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp",
    "image/gif" => "gif", "video/mp4" => "mp4", "video/webm" => "webm",
    "audio/mpeg" => "mp3", "audio/wav" => "wav", "audio/mp4" => "m4a"
  }.freeze

  # Uploads +io+ to object storage and creates the Asset row with size/checksum/
  # dimensions and provenance (spec §27). Runs in a transaction: no orphan row if
  # the upload fails.
  def self.store!(project:, asset_type:, io:, content_type:, scene: nil, storage: Storage.service, **attrs)
    bytes = io.read
    io.rewind if io.respond_to?(:rewind)
    checksum = Digest::SHA256.hexdigest(bytes)

    transaction do
      asset = new(
        project: project, scene: scene, asset_type: asset_type,
        content_type: content_type, byte_size: bytes.bytesize, checksum: checksum,
        **attrs
      )
      asset.assign_dimensions(bytes)
      asset.save!

      key = asset.storage_key.presence || asset.default_storage_key(content_type)
      storage.upload(key: key, io: StringIO.new(bytes), content_type: content_type)
      asset.update!(storage_key: key)
      asset
    end
  end

  def default_storage_key(content_type)
    ext = EXTENSIONS[content_type] || "bin"
    prefix = scene_id ? "projects/#{project_id}/scenes/#{scene_id}" : "projects/#{project_id}"
    "#{prefix}/#{public_id}.#{ext}"
  end

  def assign_dimensions(bytes)
    return unless content_type.to_s.start_with?("image/")

    size = FastImage.size(StringIO.new(bytes))
    self.width, self.height = size if size
  end

  # Time-limited URL the browser can fetch directly.
  def signed_url(expires_in: 3600, storage: Storage.service)
    return nil if storage_key.blank?

    storage.url(key: storage_key, expires_in: expires_in)
  end

  private

  def sync_ai_generated_flag
    self.ai_generated = true if source_type == "ai_generated"
  end

  def purge_storage_object
    return if storage_key.blank?

    Storage.service.delete(key: storage_key)
  rescue => e
    Rails.logger.warn("failed to purge storage object #{storage_key}: #{e.message}")
  end
end
