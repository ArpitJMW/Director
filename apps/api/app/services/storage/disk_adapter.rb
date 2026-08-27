module Storage
  # Local-filesystem backend for development and test. URLs point at a signed
  # Rails endpoint (see Api::V1::AssetFilesController) rather than a real CDN.
  class DiskAdapter < Service
    def initialize(root: Rails.root.join("storage/uploads"))
      super()
      @root = Pathname(root)
    end

    def upload(key:, io:, content_type:)
      path = path_for(key)
      path.dirname.mkpath
      io.rewind if io.respond_to?(:rewind)
      path.binwrite(io.read)
    end

    # Signed, expiring path served by the app. Absolute URL is built by the
    # caller/serializer from the current request host.
    def url(key:, expires_in: 3600)
      expires_at = expires_in.to_i.zero? ? nil : (Time.current + expires_in).to_i
      token = sign(key, expires_at)
      query = { key: key, token: token }
      query[:expires] = expires_at if expires_at
      "/api/v1/files?#{query.to_query}"
    end

    def download(key:)
      path_for(key).binread
    end

    def delete(key:)
      path_for(key).delete if path_for(key).exist?
    end

    def exists?(key:)
      path_for(key).exist?
    end

    # Verify a signed URL (called by the file controller).
    def verify(key:, token:, expires: nil)
      return false if expires.present? && Time.current.to_i > expires.to_i

      ActiveSupport::SecurityUtils.secure_compare(token.to_s, sign(key, expires))
    end

    private

    def path_for(key)
      clean = key.to_s.gsub(%r{\.\.+/?}, "")
      @root.join(clean)
    end

    def sign(key, expires)
      data = [ key, expires ].compact.join("|")
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, data)
    end
  end
end
