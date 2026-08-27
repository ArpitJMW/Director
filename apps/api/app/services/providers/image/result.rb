module Providers
  module Image
    # Normalized result of an image generation call.
    Result = Data.define(:bytes, :content_type, :model, :provider, :provider_request_id, :cost_usd, :raw) do
      def initialize(bytes:, content_type:, model:, provider:, provider_request_id:, raw:, cost_usd: 0.0)
        super
      end

      def byte_size = bytes.bytesize
      def io = StringIO.new(bytes)
    end
  end
end
