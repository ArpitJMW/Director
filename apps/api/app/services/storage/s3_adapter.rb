module Storage
  # S3 / Cloudflare R2 backend. R2 works with an explicit `endpoint` and
  # `force_path_style: true`.
  class S3Adapter < Service
    def initialize(
      bucket: ENV.fetch("S3_BUCKET"),
      region: ENV.fetch("S3_REGION", "auto"),
      endpoint: ENV["S3_ENDPOINT"].presence,
      access_key_id: ENV["S3_ACCESS_KEY_ID"],
      secret_access_key: ENV["S3_SECRET_ACCESS_KEY"]
    )
      super()
      @bucket = bucket
      options = { region: region }
      options[:endpoint] = endpoint if endpoint
      options[:force_path_style] = true if endpoint
      if access_key_id && secret_access_key
        options[:credentials] = Aws::Credentials.new(access_key_id, secret_access_key)
      end
      @client = Aws::S3::Client.new(**options)
    end

    def upload(key:, io:, content_type:)
      io.rewind if io.respond_to?(:rewind)
      @client.put_object(bucket: @bucket, key: key, body: io.read, content_type: content_type)
    end

    def url(key:, expires_in: 3600)
      Aws::S3::Presigner.new(client: @client).presigned_url(
        :get_object, bucket: @bucket, key: key, expires_in: expires_in.to_i.clamp(1, 604_800)
      )
    end

    def download(key:)
      @client.get_object(bucket: @bucket, key: key).body.read
    end

    def delete(key:)
      @client.delete_object(bucket: @bucket, key: key)
    end

    def exists?(key:)
      @client.head_object(bucket: @bucket, key: key)
      true
    rescue Aws::S3::Errors::NotFound
      false
    end
  end
end
