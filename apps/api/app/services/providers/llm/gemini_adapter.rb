require "net/http"

module Providers
  module LLM
    # Google Gemini text generation (spec §15). Free tier covers this project's
    # script / storyboard / preflight calls. Raw REST — no official Ruby SDK.
    class GeminiAdapter < Base
      HOST = "https://generativelanguage.googleapis.com/v1beta/models".freeze
      DEFAULT_MODEL = ENV.fetch("LLM_MODEL", "gemini-2.5-flash")

      def initialize(api_key: ENV["GEMINI_API_KEY"], model: DEFAULT_MODEL)
        super()
        raise Error, "GEMINI_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @model = model
      end

      def name = "gemini"
      def default_model = @model

      def chat(system:, messages:, max_tokens: 4096, model: nil)
        used_model = model || @model
        uri = URI("#{HOST}/#{used_model}:generateContent")

        body = {
          system_instruction: { parts: [ { text: system } ] },
          contents: messages.map do |m|
            { role: m[:role].to_s == "assistant" ? "model" : "user", parts: [ { text: m[:content] } ] }
          end,
          generationConfig: {
            maxOutputTokens: max_tokens,
            temperature: 0.9,
            responseMimeType: "application/json"
          }
        }

        response = post_json(uri, body)
        candidate = response.dig("candidates", 0)
        text = Array(candidate&.dig("content", "parts")).filter_map { |p| p["text"] }.join.strip
        usage = response["usageMetadata"] || {}

        raise Error, "gemini returned no text (#{candidate&.dig('finishReason')})" if text.blank?

        Result.new(
          text: text,
          model: used_model,
          provider: name,
          stop_reason: candidate["finishReason"]&.downcase,
          usage: {
            input_tokens: usage["promptTokenCount"].to_i,
            output_tokens: usage["candidatesTokenCount"].to_i
          },
          provider_request_id: response["responseId"],
          raw: response
        )
      end

      private

      def post_json(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-goog-api-key"] = @api_key
        request.body = body.to_json

        res = http.request(request)
        raise Error, "gemini HTTP #{res.code}: #{res.body.to_s[0, 500]}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      end
    end
  end
end
