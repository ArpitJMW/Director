require "net/http"

module Providers
  module Voice
    # Google Gemini text-to-speech (spec §15, §26). Works on the Gemini API key
    # even when image generation is quota-limited. Returns raw PCM which we wrap
    # in a WAV container. Gemini TTS gives no word timing, so captions use an
    # even distribution across the clip.
    class GeminiTtsAdapter < Base
      HOST = "https://generativelanguage.googleapis.com/v1beta/models".freeze
      DEFAULT_MODEL = ENV.fetch("GEMINI_TTS_MODEL", "gemini-2.5-flash-preview-tts")
      DEFAULT_VOICE = ENV.fetch("GEMINI_TTS_VOICE", "Charon")
      SAMPLE_RATE = 24_000 # Gemini TTS: L16 PCM @ 24 kHz mono

      def initialize(api_key: ENV["GEMINI_API_KEY"], model: DEFAULT_MODEL)
        super()
        raise Error, "GEMINI_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @model = model
      end

      def name = "gemini_tts"
      def default_model = @model
      def default_voice_id = DEFAULT_VOICE

      def synthesize(text:, voice_id: nil, model: nil)
        used_model = model || @model
        voice = voice_id.presence || DEFAULT_VOICE
        uri = URI("#{HOST}/#{used_model}:generateContent")

        body = {
          contents: [ { parts: [ { text: text } ] } ],
          generationConfig: {
            responseModalities: [ "AUDIO" ],
            speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } }
          }
        }

        response = post_json(uri, body)
        part = response.dig("candidates", 0, "content", "parts", 0)
        inline = part&.dig("inlineData") || part&.dig("inline_data")
        raise Error, "gemini-tts returned no audio (#{response.dig('candidates', 0, 'finishReason')})" if inline.nil?

        pcm = Base64.decode64(inline["data"])
        duration = pcm.bytesize / (2.0 * SAMPLE_RATE)

        Result.new(
          audio_bytes: wav(pcm),
          content_type: "audio/wav",
          alignment: { words: even_words(text, duration) },
          duration_seconds: duration.round(3),
          model: used_model,
          provider: name,
          provider_request_id: response["responseId"],
          cost_usd: 0.0,
          raw: nil
        )
      end

      private

      def post_json(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 180

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-goog-api-key"] = @api_key
        request.body = body.to_json

        res = http.request(request)
        raise Error, "gemini-tts HTTP #{res.code}: #{res.body.to_s[0, 400]}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      end

      def even_words(text, duration)
        tokens = text.to_s.split
        return [] if tokens.empty?

        step = duration / tokens.length
        tokens.each_with_index.map do |word, i|
          { text: word, start: (i * step).round(3), end: ((i + 1) * step).round(3) }
        end
      end

      def wav(pcm)
        data = pcm.bytesize
        header = [
          "RIFF", 36 + data, "WAVE",
          "fmt ", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16,
          "data", data
        ].pack("a4Va4a4VvvVVvva4V")
        header + pcm
      end
    end
  end
end
