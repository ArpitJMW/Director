module Providers
  module Image
    # Deterministic placeholder generator for offline dev/test. Renders a
    # gradient PNG whose colour is derived from the prompt, at the right
    # dimensions — enough to eyeball a storyboard without an API key.
    class FakeImageAdapter < Base
      def name = "fake"
      def default_model = "fake-image-1"

      def generate(prompt:, aspect_ratio: "16:9", model: nil)
        width, height = dimensions_for(aspect_ratio)
        seed = Digest::SHA256.hexdigest(prompt.to_s)[0, 6].to_i(16)
        base = ChunkyPNG::Color.from_hsv((seed % 360), 0.4, 0.85)

        png = ChunkyPNG::Image.new(width, height, base)
        height.times do |y|
          shade = ChunkyPNG::Color.fade(ChunkyPNG::Color::BLACK, (y * 90 / height))
          png.replace_row!(y, Array.new(width, ChunkyPNG::Color.compose(shade, base)))
        end

        Result.new(
          bytes: png.to_blob,
          content_type: "image/png",
          model: model || default_model,
          provider: name,
          provider_request_id: "fake_img_#{SecureRandom.hex(6)}",
          cost_usd: 0.0,
          raw: nil
        )
      end
    end
  end
end
