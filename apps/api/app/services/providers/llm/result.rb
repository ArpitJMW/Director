module Providers
  module LLM
    # Normalized result of an LLM chat call, provider-agnostic.
    Result = Data.define(:text, :model, :provider, :stop_reason, :usage, :provider_request_id, :raw) do
      # usage is a Hash: { input_tokens:, output_tokens: }
      def input_tokens = usage[:input_tokens].to_i
      def output_tokens = usage[:output_tokens].to_i
      def total_tokens = input_tokens + output_tokens
    end
  end
end
