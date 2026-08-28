require "net/http"

module Providers
  module Image
    # Cloudflare Workers AI image generation (spec §15). Free tier: 10k
    # neurons/day. Default model FLUX.1 [schnell] (1024×1024 — the renderer
    # crops to the target aspect ratio). Raw REST.
    class CloudflareAdapter < Base
      DEFAULT_MODEL = ENV.fetch("IMAGE_MODEL", "@cf/black-forest-labs/flux-1-schnell")

      def initialize(
        account_id: ENV["CLOUDFLARE_ACCOUNT_ID"],
        api_token: ENV["CLOUDFLARE_API_TOKEN"],
        model: DEFAULT_MODEL
      )
        super()
        raise Error, "CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN not set" if account_id.blank? || api_token.blank?

        @account_id = account_id
        @api_token = api_token
        @model = model
      end

      def name = "cloudflare"
      def default_model = @model

      def generate(prompt:, aspect_ratio: "16:9", negative_prompt: nil, seed: nil, model: nil)
        used_model = model || @model
        uri = URI("https://api.cloudflare.com/client/v4/accounts/#{@account_id}/ai/run/#{used_model}")

        payload = { prompt: prompt, steps: 4 }
        # SDXL-family models accept these; FLUX schnell ignores them.
        payload[:negative_prompt] = negative_prompt if negative_prompt.present?
        payload[:seed] = seed if seed
        res = post(uri, payload)
        bytes, content_type = extract_image(res)

        Result.new(
          bytes: bytes,
          content_type: content_type,
          model: used_model,
          provider: name,
          provider_request_id: res["x-request-id"],
          cost_usd: Providers::Pricing.image_cost_usd(provider: name, model: used_model),
          raw: nil
        )
      end

      private

      def post(uri, payload)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_token}"
        request["Content-Type"] = "application/json"
        request.body = payload.to_json

        response = http.request(request)
        raise Error, "cloudflare HTTP #{response.code}: #{response.body.to_s[0, 500]}" unless response.code.to_i.between?(200, 299)

        response
      end

      # FLUX schnell returns JSON { result: { image: "<base64 jpeg>" } };
      # some CF image models return raw binary. Handle both.
      def extract_image(response)
        if response.content_type.to_s.include?("application/json")
          data = JSON.parse(response.body)
          b64 = data.dig("result", "image") or raise Error, "cloudflare returned no image: #{response.body[0, 300]}"
          [ Base64.decode64(b64), "image/jpeg" ]
        else
          [ response.body, response.content_type.presence || "image/png" ]
        end
      end
    end
  end
end
