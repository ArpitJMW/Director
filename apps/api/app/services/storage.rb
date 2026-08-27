module Storage
  module_function

  # The configured object-storage backend. `STORAGE_BACKEND` = "disk" | "s3".
  # Defaults to disk unless an S3 bucket is configured.
  def service
    @service ||= build_service
  end

  def service=(adapter)
    @service = adapter
  end

  def reset!
    @service = nil
  end

  def build_service
    backend = ENV["STORAGE_BACKEND"].presence
    backend ||= ENV["S3_BUCKET"].present? ? "s3" : "disk"

    case backend
    when "disk" then DiskAdapter.new
    when "s3" then S3Adapter.new
    else raise ArgumentError, "unknown STORAGE_BACKEND: #{backend.inspect}"
    end
  end
end
