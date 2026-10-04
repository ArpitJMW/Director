module Providers
  module Voice
    # Interface for text-to-speech providers (spec §15, §26).
    class Base
      Error = Class.new(StandardError)

      # @return [Providers::Voice::Result]
      def synthesize(text:, voice_id: nil, model: nil)
        raise NotImplementedError
      end

      # True for providers that benefit from one call covering many scenes'
      # narration at once (Phase 1 Task 2.4 — e.g. a severe per-request quota
      # that per-scene calls blow through immediately). Media::VoiceJob checks
      # this to decide whether to route a project through
      # Media::BatchVoiceGenerationService or the existing per-scene path.
      def supports_batch? = false

      # Only implemented when #supports_batch? is true.
      # @param texts [Array<String>] one project's scenes' narration, in order
      # @return [Array<Providers::Voice::Result, nil>] one entry per input
      #   text, same order, each independently playable/captionable. An
      #   individual entry may be nil (a subset failed and was tolerated —
      #   AiGeneration.track! and Media::BatchVoiceGenerationService both
      #   handle nils), but the array must contain at least one non-nil
      #   entry — raise instead of returning an all-nil array.
      def synthesize_batch(texts:, voice_id: nil, model: nil)
        raise NotImplementedError
      end

      def name = raise NotImplementedError
      def default_model = raise NotImplementedError
      def default_voice_id = raise NotImplementedError
    end
  end
end
