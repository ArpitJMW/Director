module Providers
  module LLM
    class AnthropicAdapter < Base
      DEFAULT_MODEL = ENV.fetch("LLM_MODEL", "claude-opus-5")

      def initialize(api_key: ENV["ANTHROPIC_API_KEY"], model: DEFAULT_MODEL)
        super()
        @client = Anthropic::Client.new(api_key: api_key)
        @model = model
      end

      def name = "anthropic"
      def default_model = @model

      def chat(system:, messages:, max_tokens: 4096, model: nil)
        used_model = model || @model
        message = @client.messages.create(
          model: used_model.to_sym,
          max_tokens: max_tokens,
          thinking: { type: "adaptive" },
          system_: [ { type: "text", text: system } ],
          messages: messages.map { |m| { role: m[:role].to_s, content: m[:content] } }
        )

        text = message.content.select { |b| b.type == :text }.map(&:text).join("\n").strip

        Result.new(
          text: text,
          model: used_model,
          provider: name,
          stop_reason: message.stop_reason&.to_s,
          usage: {
            input_tokens: message.usage.input_tokens,
            output_tokens: message.usage.output_tokens
          },
          provider_request_id: message.id,
          raw: message
        )
      rescue Anthropic::Errors::APIStatusError => e
        raise Error, "anthropic #{e.type || e.class}: #{e.message}"
      end
    end
  end
end
