require "open3"
require "tmpdir"

module Providers
  module Voice
    # Microsoft Edge TTS (spec §15, §26). Free, no API key, word-level timing.
    # Shells out to the Node helper in apps/renderer (installed via `pnpm install`).
    class EdgeTtsAdapter < Base
      DEFAULT_VOICE = ENV.fetch("EDGE_TTS_VOICE", "en-US-AriaNeural")

      def self.command
        ENV["EDGE_TTS_COMMAND"].presence ||
          "node #{Rails.root.join('../renderer/edge-tts.mjs')}"
      end

      def initialize(command: self.class.command)
        super()
        @command = command
      end

      def name = "edge_tts"
      def default_model = "edge-neural"
      def default_voice_id = DEFAULT_VOICE

      def synthesize(text:, voice_id: nil, model: nil)
        voice = voice_id.presence || DEFAULT_VOICE

        Dir.mktmpdir("clipify-tts") do |dir|
          out = File.join(dir, "audio.mp3")
          stdout, stderr, status = Open3.capture3(*@command.split, voice, out, stdin_data: text)
          raise Error, "edge-tts failed (#{status.exitstatus}): #{stderr.strip.last(400)}" unless status.success?
          raise Error, "edge-tts produced no audio" unless File.exist?(out) && File.size(out).positive?

          meta = JSON.parse(stdout)
          words = Array(meta["words"]).map(&:symbolize_keys)

          Result.new(
            audio_bytes: File.binread(out),
            content_type: "audio/mpeg",
            alignment: { words: words },
            duration_seconds: meta["duration"].to_f,
            model: model || default_model,
            provider: name,
            provider_request_id: nil,
            cost_usd: 0.0,
            raw: nil
          )
        end
      end
    end
  end
end
