module Providers
  module LLM
    # Interface for LLM providers (spec §15). Business logic depends only on this,
    # never on a concrete vendor.
    class Base
      Error = Class.new(StandardError)

      # @param system [String]
      # @param messages [Array<Hash{role: String, content: String}>]
      # @param max_tokens [Integer]
      # @param model [String, nil] override the provider default
      # @return [Providers::LLM::Result]
      def chat(system:, messages:, max_tokens: 4096, model: nil)
        raise NotImplementedError
      end

      # Short provider key stored on ai_generations.provider
      def name
        raise NotImplementedError
      end

      def default_model
        raise NotImplementedError
      end
    end
  end
end
