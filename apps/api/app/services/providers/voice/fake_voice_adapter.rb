module Providers
  module Voice
    # Offline stand-in: emits a silent WAV whose length tracks the text, plus
    # evenly-spaced per-character alignment. Enough for the caption pipeline and
    # renderer to run without an API key.
    class FakeVoiceAdapter < Base
      SAMPLE_RATE = 22_050
      CHARS_PER_SECOND = 15.0

      def name = "fake"
      def default_model = "fake-voice-1"
      def default_voice_id = "fake-voice"

      def synthesize(text:, voice_id: nil, model: nil)
        chars = text.to_s.chars
        duration = [ chars.length / CHARS_PER_SECOND, 0.8 ].max.round(3)

        Result.new(
          audio_bytes: silent_wav(duration),
          content_type: "audio/wav",
          alignment: even_alignment(chars, duration),
          duration_seconds: duration,
          model: model || default_model,
          provider: name,
          provider_request_id: "fake_tts_#{SecureRandom.hex(6)}",
          cost_usd: 0.0,
          raw: nil
        )
      end

      private

      def even_alignment(chars, duration)
        step = chars.empty? ? 0 : duration / chars.length
        starts = chars.each_index.map { |i| (i * step).round(4) }
        ends = chars.each_index.map { |i| ((i + 1) * step).round(4) }
        { characters: chars, starts: starts, ends: ends }
      end

      def silent_wav(duration)
        samples = (SAMPLE_RATE * duration).to_i
        data_bytes = samples * 2 # 16-bit mono
        [
          "RIFF", 36 + data_bytes, "WAVE",
          "fmt ", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16,
          "data", data_bytes
        ].pack("a4Va4a4VvvVVvva4V") + ("\x00" * data_bytes)
      end
    end
  end
end
