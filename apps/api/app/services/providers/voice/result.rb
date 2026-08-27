module Providers
  module Voice
    # Normalized result of a text-to-speech call.
    # alignment: { characters: [String], starts: [Float], ends: [Float] } (seconds)
    Result = Data.define(:audio_bytes, :content_type, :alignment, :duration_seconds,
                         :model, :provider, :provider_request_id, :cost_usd, :raw) do
      def initialize(audio_bytes:, content_type:, alignment:, duration_seconds:, model:,
                     provider:, provider_request_id:, raw:, cost_usd: 0.0)
        super
      end

      def io = StringIO.new(audio_bytes)
      def byte_size = audio_bytes.bytesize
    end
  end
end
