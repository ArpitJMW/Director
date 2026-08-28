require "net/http"

module Providers
  module LLM
    # Groq — OpenAI-compatible chat completions on their LPU hardware. Genuinely
    # free developer tier (rate-limited, no per-token charge). Spec §15.
    class GroqAdapter < Base
      ENDPOINT = URI("https://api.groq.com/openai/v1/chat/completions").freeze
      DEFAULT_MODEL = ENV.fetch("LLM_MODEL", "openai/gpt-oss-120b")

      def initialize(api_key: ENV["GROQ_API_KEY"], model: DEFAULT_MODEL)
        super()
        raise Error, "GROQ_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @model = model
      end

      def name = "groq"
      def default_model = @model

      def chat(system:, messages:, max_tokens: 4096, model: nil)
        used_model = model || @model
        payload = {
          model: used_model,
          messages: [ { role: "system", content: system } ] +
                    messages.map { |m| { role: m[:role].to_s, content: m[:content] } },
          max_tokens: max_tokens,
          temperature: 0.9,
          # Our prompts all instruct "respond with only JSON" (required for this mode).
          response_format: { type: "json_object" }
        }

        body = post_json(payload)
        choice = body.dig("choices", 0) or raise Error, "groq returned no choices: #{body.inspect[0, 300]}"
        usage = body["usage"] || {}

        Result.new(
          text: choice.dig("message", "content").to_s.strip,
          model: used_model,
          provider: name,
          stop_reason: choice["finish_reason"],
          usage: {
            input_tokens: usage["prompt_tokens"].to_i,
            output_tokens: usage["completion_tokens"].to_i
          },
          provider_request_id: body["id"],
          raw: body
        )
      end

      private

      def post_json(payload)
        http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(ENDPOINT)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = payload.to_json

        res = http.request(request)
        raise Error, "groq HTTP #{res.code}: #{res.body.to_s[0, 500]}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      end
    end
  end
end
