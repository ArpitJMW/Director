module Providers
  # Provider list prices (USD per 1M tokens). Used to attribute cost to every
  # ai_generation (spec §34/§37). Update as vendor pricing changes.
  module Pricing
    TABLE = {
      "anthropic" => {
        "claude-opus-5" => { input: 5.0, output: 25.0 },
        "claude-sonnet-5" => { input: 2.0, output: 10.0 },
        "claude-haiku-4-5" => { input: 1.0, output: 5.0 }
      }
    }.freeze

    # Flat USD cost per generated image.
    IMAGE_TABLE = {
      "gemini" => { "gemini-2.5-flash-image" => 0.039 }
    }.freeze

    module_function

    def cost_usd(provider:, model:, input_tokens:, output_tokens:)
      rates = TABLE.dig(provider.to_s, model.to_s)
      return 0.0 unless rates

      ((input_tokens * rates[:input]) + (output_tokens * rates[:output])) / 1_000_000.0
    end

    def image_cost_usd(provider:, model:, images: 1)
      rate = IMAGE_TABLE.dig(provider.to_s, model.to_s) || 0.0
      rate * images
    end
  end
end
