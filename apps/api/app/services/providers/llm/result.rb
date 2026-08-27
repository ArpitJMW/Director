module Providers
  module LLM
    # Normalized result of an LLM chat call, provider-agnostic.
    # cost_usd is optional — nil means "derive it from token usage".
    Result = Data.define(:text, :model, :provider, :stop_reason, :usage, :provider_request_id, :cost_usd, :raw) do
      def initialize(text:, model:, provider:, stop_reason:, usage:, provider_request_id:, raw:, cost_usd: nil)
        super
      end

      def input_tokens = usage[:input_tokens].to_i
      def output_tokens = usage[:output_tokens].to_i
      def total_tokens = input_tokens + output_tokens
    end
  end
end
