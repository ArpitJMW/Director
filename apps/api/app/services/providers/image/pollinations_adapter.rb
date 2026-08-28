require "net/http"
require "erb"

module Providers
  module Image
    # Pollinations.ai — free text-to-image, no API key. Spec §15.
    # GET https://image.pollinations.ai/prompt/<prompt>?width=&height=&model=
    class PollinationsAdapter < Base
      HOST = "https://image.pollinations.ai/prompt".freeze
      DEFAULT_MODEL = ENV.fetch("IMAGE_MODEL", "flux")

      def initialize(model: DEFAULT_MODEL, token: ENV["POLLINATIONS_TOKEN"].presence)
        super()
        @model = model
        @token = token
      end

      def name = "pollinations"
      def default_model = @model

      def generate(prompt:, aspect_ratio: "16:9", negative_prompt: nil, seed: nil, model: nil)
        width, height = dimensions_for(aspect_ratio)
        used_model = model || @model

        # Pollinations has no separate negative field — fold it into the prompt.
        full_prompt = prompt.to_s
        full_prompt += " | avoid: #{negative_prompt}" if negative_prompt.present?

        params = { width: width, height: height, model: used_model, nologo: "true", safe: "true", enhance: "true" }
        params[:seed] = seed if seed
        params[:token] = @token if @token
        uri = URI("#{HOST}/#{ERB::Util.url_encode(full_prompt)}?#{URI.encode_www_form(params)}")

        bytes, content_type = fetch(uri)

        Result.new(
          bytes: bytes,
          content_type: content_type,
          model: used_model,
          provider: name,
          provider_request_id: nil,
          cost_usd: 0.0,
          raw: nil
        )
      end

      private

      def fetch(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 180 # pollinations can be slow under load

        res = http.request(Net::HTTP::Get.new(uri))
        raise Error, "pollinations HTTP #{res.code}: #{res.body.to_s[0, 300]}" unless res.code.to_i.between?(200, 299)
        raise Error, "pollinations returned #{res.content_type}" unless res.content_type.to_s.start_with?("image/")

        [ res.body, res.content_type ]
      end
    end
  end
end
