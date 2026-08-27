require "net/http"

module Providers
  module Voice
    # ElevenLabs TTS with character timestamps (spec §26, §48). Raw REST — no
    # official Ruby SDK. Untested against the live API until an ELEVENLABS_API_KEY
    # is available; shape follows the documented `/with-timestamps` endpoint.
    class ElevenLabsAdapter < Base
      HOST = "https://api.elevenlabs.io".freeze
      DEFAULT_MODEL = ENV.fetch("ELEVENLABS_MODEL", "eleven_multilingual_v2")
      COST_PER_CHAR_USD = 0.00018

      def initialize(api_key: ENV["ELEVENLABS_API_KEY"], voice_id: ENV["ELEVENLABS_VOICE_ID"], model: DEFAULT_MODEL)
        super()
        raise Error, "ELEVENLABS_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @voice_id = voice_id.presence || "21m00Tcm4TlvDq8ikWAM" # "Rachel"
        @model = model
      end

      def name = "elevenlabs"
      def default_model = @model
      def default_voice_id = @voice_id

      def synthesize(text:, voice_id: nil, model: nil)
        vid = voice_id.presence || @voice_id
        uri = URI("#{HOST}/v1/text-to-speech/#{vid}/with-timestamps")
        payload = { text: text, model_id: model || @model, output_format: "mp3_44100_128" }

        body = post_json(uri, payload)
        alignment = normalize_alignment(body["alignment"] || body["normalized_alignment"])

        Result.new(
          audio_bytes: Base64.decode64(body.fetch("audio_base64")),
          content_type: "audio/mpeg",
          alignment: alignment,
          duration_seconds: alignment[:ends].last || 0.0,
          model: model || @model,
          provider: name,
          provider_request_id: nil,
          cost_usd: text.to_s.length * COST_PER_CHAR_USD,
          raw: body.except("audio_base64")
        )
      end

      private

      def post_json(uri, payload)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["xi-api-key"] = @api_key
        request["Content-Type"] = "application/json"
        request.body = payload.to_json

        res = http.request(request)
        raise Error, "elevenlabs HTTP #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      end

      def normalize_alignment(data)
        return { characters: [], starts: [], ends: [] } if data.blank?

        {
          characters: data["characters"] || [],
          starts: data["character_start_times_seconds"] || [],
          ends: data["character_end_times_seconds"] || []
        }
      end
    end
  end
end
