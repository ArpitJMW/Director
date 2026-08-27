module Storage
  # Interface for object storage (spec §12). Business logic depends only on this.
  class Service
    Error = Class.new(StandardError)

    # @param key [String] object key, e.g. "projects/1/assets/ast_x.png"
    # @param io [IO] readable stream
    # @param content_type [String]
    # @return [void]
    def upload(key:, io:, content_type:)
      raise NotImplementedError
    end

    # A time-limited URL the browser can GET directly.
    def url(key:, expires_in: 3600)
      raise NotImplementedError
    end

    def download(key:)
      raise NotImplementedError
    end

    def delete(key:)
      raise NotImplementedError
    end

    def exists?(key:)
      raise NotImplementedError
    end
  end
end
