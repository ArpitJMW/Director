require "net/http"

module Providers
  module Qa
    # Google Gemini vision review of one generated image (Task 6 Part B). Model
    # choice and the reasoning behind it are in the Task 6 report. Raw REST, like
    # the other Gemini adapters.
    class GeminiVisionAdapter
      Error = Class.new(StandardError)
      RateLimited = Class.new(Error)

      HOST = "https://generativelanguage.googleapis.com/v1beta/models".freeze
      DEFAULT_MODEL = ENV.fetch("QA_MODEL", "gemini-3.5-flash")
      # Gemini thinking tokens count against maxOutputTokens: a 300-token cap
      # was exhausted by thinking alone during probing, truncating the JSON.
      MAX_OUTPUT_TOKENS = 2048
      TRANSIENT_RETRY_DELAYS = [ 5, 15 ].freeze

      def initialize(api_key: ENV["GEMINI_API_KEY"], model: DEFAULT_MODEL, sleeper: method(:sleep))
        raise Error, "GEMINI_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @model = model
        @sleeper = sleeper
      end

      def name = "gemini"
      def default_model = @model

      # @return [Providers::LLM::Result]
      def review(image_bytes:, content_type:, prompt:)
        generate([ { text: prompt },
                   inline_part(image_bytes, content_type) ], MAX_OUTPUT_TOKENS)
      end

      # Several images in one request (Task 6.2 Part 0a). Each image is preceded
      # by its id so the reply can be matched back to its unit.
      # @param images [Array<Hash>] { id:, bytes:, content_type: }
      def review_batch(images:, prompt:)
        parts = [ { text: prompt } ]
        images.each do |im|
          parts << { text: "Image id: #{im[:id]}" }
          parts << inline_part(im[:bytes], im[:content_type])
        end
        generate(parts, MAX_OUTPUT_TOKENS * BATCH_OUTPUT_FACTOR)
      end

      private

      BATCH_OUTPUT_FACTOR = 4

      def inline_part(bytes, content_type)
        { inline_data: { mime_type: content_type.presence || "image/jpeg", data: Base64.strict_encode64(bytes) } }
      end

      def generate(parts, max_tokens)
        uri = URI("#{HOST}/#{@model}:generateContent")
        body = {
          contents: [ { parts: parts } ],
          generationConfig: { responseMimeType: "application/json", maxOutputTokens: max_tokens, temperature: 0.1 }
        }

        response = post_with_retry(uri, body)
        candidate = response.dig("candidates", 0)
        text = Array(candidate&.dig("content", "parts")).filter_map { |p| p["text"] }.join.strip
        raise Error, "gemini vision returned no text (#{candidate&.dig('finishReason')})" if text.blank?

        usage = response["usageMetadata"] || {}
        LLM::Result.new(
          text: text, model: @model, provider: name,
          stop_reason: candidate["finishReason"]&.downcase,
          usage: { input_tokens: usage["promptTokenCount"].to_i, output_tokens: usage["candidatesTokenCount"].to_i },
          provider_request_id: response["responseId"],
          raw: { estimated_cost_usd: Providers::Pricing.list_cost_usd(
            provider: name, model: @model,
            input_tokens: usage["promptTokenCount"].to_i, output_tokens: usage["candidatesTokenCount"].to_i
          ), response: response }
        )
      end

      # 429 is never retried: it is the signal to stop the run. 503 (overload)
      # is retried a small bounded number of times, then reported.
      def post_with_retry(uri, body)
        attempts = 0
        begin
          post_json(uri, body)
        rescue Error => e
          raise if e.is_a?(RateLimited) || attempts >= TRANSIENT_RETRY_DELAYS.size || !e.message.include?("HTTP 503")

          @sleeper.call(TRANSIENT_RETRY_DELAYS[attempts])
          attempts += 1
          retry
        end
      end

      def post_json(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-goog-api-key"] = @api_key
        request.body = body.to_json

        res = http.request(request)
        code = res.code.to_i
        raise RateLimited, "gemini vision HTTP 429: quota exhausted" if code == 429
        raise Error, "gemini vision HTTP #{code}: #{res.body.to_s[0, 300]}" unless code.between?(200, 299)

        JSON.parse(res.body)
      end
    end
  end
end
