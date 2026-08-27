module Providers
  module Voice
    # Interface for text-to-speech providers (spec §15, §26).
    class Base
      Error = Class.new(StandardError)

      # @return [Providers::Voice::Result]
      def synthesize(text:, voice_id: nil, model: nil)
        raise NotImplementedError
      end

      def name = raise NotImplementedError
      def default_model = raise NotImplementedError
      def default_voice_id = raise NotImplementedError
    end
  end
end
