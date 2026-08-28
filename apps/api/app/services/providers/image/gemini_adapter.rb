require "net/http"

module Providers
  module Image
    # Google Gemini image generation ("Nano Banana", spec §15/§48). Raw REST —
    # no official Ruby SDK. Untested against the live API until a GEMINI_API_KEY
    # is available; the request/response shape follows the documented
    # generateContent image API.
    class GeminiAdapter < Base
      DEFAULT_MODEL = ENV.fetch("IMAGE_MODEL", "gemini-2.5-flash-image")
      ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models".freeze

      def initialize(api_key: ENV["GEMINI_API_KEY"], model: DEFAULT_MODEL)
        super()
        raise Error, "GEMINI_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @model = model
      end

      def name = "gemini"
      def default_model = @model

      def generate(prompt:, aspect_ratio: "16:9", negative_prompt: nil, seed: nil, model: nil)
        used_model = model || @model
        uri = URI("#{ENDPOINT}/#{used_model}:generateContent")

        text = "#{prompt}\n\nAspect ratio: #{aspect_ratio}."
        text += "\nAvoid: #{negative_prompt}." if negative_prompt.present?

        body = {
          contents: [ { parts: [ { text: text } ] } ],
          generationConfig: { responseModalities: [ "IMAGE" ] }
        }

        response = post_json(uri, body)
        part = dig_image_part(response)
        raise Error, "gemini returned no image (#{response.dig('promptFeedback', 'blockReason')})" if part.nil?

        Result.new(
          bytes: Base64.decode64(part["data"]),
          content_type: part["mimeType"] || "image/png",
          model: used_model,
          provider: name,
          provider_request_id: response["responseId"],
          cost_usd: Providers::Pricing.image_cost_usd(provider: name, model: used_model),
          raw: response
        )
      end

      private

      def post_json(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 60

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-goog-api-key"] = @api_key
        request.body = body.to_json

        res = http.request(request)
        raise Error, "gemini HTTP #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      end

      def dig_image_part(response)
        parts = response.dig("candidates", 0, "content", "parts") || []
        parts.map { |p| p["inlineData"] || p["inline_data"] }.compact.first
      end
    end
  end
end
