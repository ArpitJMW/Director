module Providers
  # Per-project spend (Task 5B). `estimate` is what the assets and voice stages
  # are expected to cost before they run; `actual` is what the project's own
  # ai_generations recorded. Both in USD.
  module CostReport
    # Gemini TTS bills audio at 25 output tokens per second of audio.
    VOICE_OUTPUT_TOKENS_PER_SECOND = 25
    # Rough text-to-token ratio for the input side of an estimate.
    CHARS_PER_INPUT_TOKEN = 4

    module_function

    def estimate(project)
      image = image_estimate(project)
      voice = voice_estimate(project)
      {
        image: image,
        voice: voice,
        total_usd: (image[:usd].to_f + voice[:usd].to_f).round(4)
      }
    end

    def actual(project)
      by_stage = project.ai_generations.group(:provider, :kind).sum(:cost_usd)
      {
        total_usd: by_stage.values.sum.to_f.round(4),
        by_stage: by_stage.map do |(provider, kind), usd|
          { provider: provider, kind: kind, usd: usd.to_f.round(4) }
        end
      }
    end

    def image_estimate(project)
      units = pending_image_units(project)
      adapter = Providers.image
      rate = Pricing.image_cost_usd(provider: adapter.name, model: adapter.default_model)
      { provider: adapter.name, model: adapter.default_model, units: units,
        rate_usd: rate, usd: (units * rate).round(4) }
    rescue PaidProviderBlocked => e
      { blocked: e.message, units: units, usd: nil }
    end

    def voice_estimate(project)
      adapter = Providers.voice
      scenes = project.scenes.where.not(narration: [ nil, "" ]).to_a
      usd = scenes.sum do |scene|
        Pricing.cost_usd(
          provider: adapter.name, model: adapter.default_model,
          input_tokens: scene.narration.length / CHARS_PER_INPUT_TOKEN,
          output_tokens: (scene.duration_seconds.to_f * VOICE_OUTPUT_TOKENS_PER_SECOND).round
        )
      end
      { provider: adapter.name, model: adapter.default_model, units: scenes.size, usd: usd.round(4) }
    rescue PaidProviderBlocked => e
      { blocked: e.message, units: scenes&.size || 0, usd: nil }
    end

    # Units an assets run still has to produce: each shot when a scene has
    # shots, otherwise the scene itself — and only image-strategy ones.
    def pending_image_units(project)
      project.scenes.includes(:shots).sum do |scene|
        next 0 unless scene.asset_strategy == "image"

        units = scene.shots.to_a.presence || [ scene ]
        units.count { |unit| unit.status != "ready" }
      end
    end
  end
end
