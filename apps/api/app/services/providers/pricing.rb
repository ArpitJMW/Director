module Providers
  # Provider list prices, used to attribute cost to every ai_generation
  # (spec §34/§37).
  #
  # Source for every Gemini figure below: https://ai.google.dev/gemini-api/docs/pricing
  # (read 2026-10-03, standard — not batch — tier, USD). Update when that page
  # changes.
  #
  # Task 5B: real costs, not $0. A paid model with no rate here is treated as
  # unknown: cost falls back to 0.0 and a warning is logged, so a missing rate
  # is loud rather than silent.
  module Pricing
    # USD per 1M tokens (text/LLM and TTS).
    TABLE = {
      "anthropic" => {
        "claude-opus-5" => { input: 5.0, output: 25.0 },
        "claude-sonnet-5" => { input: 2.0, output: 10.0 },
        "claude-haiku-4-5" => { input: 1.0, output: 5.0 }
      },
      "gemini" => {
        # Source: https://ai.google.dev/gemini-api/docs/pricing (read 2026-10-03).
        # gemini-3.5-flash: "$1.50/$9.00 per 1M tokens" (standard tier), free tier listed.
        "gemini-3.5-flash" => { input: 1.50, output: 9.00 },
        # LLM. Free tier exists for flash / flash-lite.
        "gemini-2.5-flash" => { input: 0.30, output: 2.50 },
        "gemini-2.5-flash-lite" => { input: 0.10, output: 0.40 },
        # TTS. Preview flash has a free tier; pro preview does not.
        "gemini-2.5-flash-preview-tts" => { input: 0.50, output: 10.00 },
        "gemini-2.5-pro-preview-tts" => { input: 1.00, output: 20.00 }
      },
      # Groq's developer tier has no per-token charge.
      "groq" => Hash.new({ input: 0.0, output: 0.0 })
    }.freeze

    # USD per generated image (standard tier). Free providers list 0.0.
    IMAGE_TABLE = {
      "gemini" => {
        "gemini-2.5-flash-image" => 0.039,
        "gemini-3.1-flash-image" => 0.067,   # "Nano Banana 2"
        "gemini-3-pro-image" => 0.134        # "Nano Banana Pro", per 1K/2K image
      },
      "cloudflare" => Hash.new(0.0),
      "pollinations" => Hash.new(0.0)
    }.freeze

    # Gemini models with a free tier on the same pricing page. Any other paid
    # provider is paid for every model. Used by the paid-provider guard.
    GEMINI_FREE_TIER_MODELS = %w[
      gemini-2.5-flash gemini-2.5-flash-lite gemini-2.5-flash-preview-tts gemini-3.5-flash
    ].freeze

    # Always charged, whatever the model.
    ALWAYS_PAID_PROVIDERS = %w[anthropic elevenlabs].freeze

    # Adapter names that bill under another provider's pricing rows.
    PROVIDER_ALIASES = { "gemini_tts" => "gemini" }.freeze

    module_function

    def normalize(provider)
      name = provider.to_s
      PROVIDER_ALIASES.fetch(name, name)
    end

    # True when using this provider/model costs money on the current keys.
    def paid?(provider, model)
      provider = normalize(provider)
      return true if ALWAYS_PAID_PROVIDERS.include?(provider)
      return !GEMINI_FREE_TIER_MODELS.include?(model.to_s) if provider == "gemini"

      false
    end

    # What the call actually costs us: $0 for a free-tier model on a free-tier
    # key (GEMINI_KEY_TIER=free, the default); list price otherwise (Task 6 F).
    def cost_usd(provider:, model:, input_tokens:, output_tokens:)
      return 0.0 if free_tier_billing?(provider, model)

      list_cost_usd(provider: provider, model: model, input_tokens: input_tokens, output_tokens: output_tokens)
    end

    # The list-price estimate, always, regardless of the key's tier.
    def list_cost_usd(provider:, model:, input_tokens:, output_tokens:)
      rates = TABLE.dig(normalize(provider), model.to_s)
      if rates.nil?
        warn_unknown(provider, model) if paid?(provider, model)
        return 0.0
      end

      ((input_tokens * rates[:input]) + (output_tokens * rates[:output])) / 1_000_000.0
    end

    def free_tier_billing?(provider, model)
      normalize(provider) == "gemini" &&
        ENV.fetch("GEMINI_KEY_TIER", "free") == "free" &&
        GEMINI_FREE_TIER_MODELS.include?(model.to_s)
    end

    def image_cost_usd(provider:, model:, images: 1)
      rate = IMAGE_TABLE.dig(normalize(provider), model.to_s)
      if rate.nil?
        warn_unknown(provider, model) if paid?(provider, model)
        return 0.0
      end

      rate * images
    end

    def warn_unknown(provider, model)
      Rails.logger.warn("[pricing] no rate for paid model #{provider}/#{model} — cost recorded as $0; add it to Providers::Pricing")
    end
  end
end
