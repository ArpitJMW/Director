require "rails_helper"

def with_key_tier(tier)
  saved = ENV["GEMINI_KEY_TIER"]
  ENV["GEMINI_KEY_TIER"] = tier
  yield
ensure
  saved.nil? ? ENV.delete("GEMINI_KEY_TIER") : ENV["GEMINI_KEY_TIER"] = saved
end

RSpec.describe Providers::Pricing do
  describe "Gemini image rates (official pricing page, 2026-10-03)" do
    it "prices every Gemini image model from the official table" do
      expect(described_class.image_cost_usd(provider: "gemini", model: "gemini-2.5-flash-image")).to eq(0.039)
      expect(described_class.image_cost_usd(provider: "gemini", model: "gemini-3.1-flash-image")).to eq(0.067)
      expect(described_class.image_cost_usd(provider: "gemini", model: "gemini-3-pro-image")).to eq(0.134)
    end

    it "multiplies by the number of images" do
      expect(described_class.image_cost_usd(provider: "gemini", model: "gemini-3-pro-image", images: 11)).to be_within(1e-9).of(1.474)
    end

    it "records 0 for free providers without warning" do
      expect(Rails.logger).not_to receive(:warn)
      expect(described_class.image_cost_usd(provider: "cloudflare", model: "@cf/black-forest-labs/flux-1-schnell")).to eq(0.0)
    end

    it "warns (never silently $0) for a paid image model with no rate" do
      expect(Rails.logger).to receive(:warn).with(/no rate for paid model gemini\/gemini-9-mystery-image/)
      expect(described_class.image_cost_usd(provider: "gemini", model: "gemini-9-mystery-image")).to eq(0.0)
    end
  end

  describe "Gemini TTS rates" do
    around { |ex| with_key_tier("paid") { ex.run } }

    it "prices flash-preview TTS per million text-in / audio-out tokens" do
      cost = described_class.cost_usd(provider: "gemini_tts", model: "gemini-2.5-flash-preview-tts",
                                      input_tokens: 1_000_000, output_tokens: 100_000)
      expect(cost).to be_within(1e-9).of(1.5) # 1M × $0.50 + 0.1M × $10.00
    end

    it "bills $0 on a free-tier key but still reports the list price" do
      with_key_tier("free") do
        billed = described_class.cost_usd(provider: "gemini_tts", model: "gemini-2.5-flash-preview-tts",
                                          input_tokens: 1_000_000, output_tokens: 100_000)
        list = described_class.list_cost_usd(provider: "gemini_tts", model: "gemini-2.5-flash-preview-tts",
                                             input_tokens: 1_000_000, output_tokens: 100_000)
        expect(billed).to eq(0.0)
        expect(list).to be_within(1e-9).of(1.5)
      end
    end

    it "never makes a paid model free, even on a free-tier key" do
      with_key_tier("free") do
        expect(described_class.free_tier_billing?("gemini", "gemini-3-pro-image")).to be false
      end
    end

    it "maps the gemini_tts adapter name onto the gemini pricing rows" do
      expect(described_class.normalize("gemini_tts")).to eq("gemini")
    end
  end

  describe ".paid?" do
    it "treats Gemini image models as paid (no free tier on the pricing page)" do
      expect(described_class.paid?("gemini", "gemini-3-pro-image")).to be true
      expect(described_class.paid?("gemini", "gemini-3.1-flash-image")).to be true
    end

    it "treats free-tier Gemini TTS and LLM models as free" do
      expect(described_class.paid?("gemini_tts", "gemini-2.5-flash-preview-tts")).to be false
      expect(described_class.paid?("gemini", "gemini-2.5-flash")).to be false
    end

    it "treats the pro TTS preview (no free tier) as paid" do
      expect(described_class.paid?("gemini_tts", "gemini-2.5-pro-preview-tts")).to be true
    end

    it "treats Anthropic and ElevenLabs as always paid, Cloudflare/Groq/fake as free" do
      expect(described_class.paid?("anthropic", "claude-haiku-4-5")).to be true
      expect(described_class.paid?("elevenlabs", "eleven_turbo_v2")).to be true
      expect(described_class.paid?("cloudflare", "@cf/black-forest-labs/flux-1-schnell")).to be false
      expect(described_class.paid?("groq", "openai/gpt-oss-120b")).to be false
      expect(described_class.paid?("fake", "fake-image-1")).to be false
    end
  end
end

RSpec.describe "Providers paid-provider guard (Task 5B)" do
  around do |example|
    Providers.reset!
    example.run
    Providers.reset!
  end

  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [ k, ENV[k] ] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  it "refuses a paid Gemini image model by default and names the env var" do
    with_env("IMAGE_PROVIDER" => "gemini", "IMAGE_MODEL" => "gemini-3-pro-image",
             "GEMINI_API_KEY" => "test-key", "ALLOW_PAID_PROVIDERS" => nil) do
      expect { Providers.build_image }
        .to raise_error(Providers::PaidProviderBlocked, /ALLOW_PAID_PROVIDERS=true/)
    end
  end

  it "refuses when ALLOW_PAID_PROVIDERS is set to anything other than 'true'" do
    with_env("IMAGE_PROVIDER" => "gemini", "IMAGE_MODEL" => "gemini-3-pro-image",
             "GEMINI_API_KEY" => "test-key", "ALLOW_PAID_PROVIDERS" => "yes") do
      expect { Providers.build_image }.to raise_error(Providers::PaidProviderBlocked)
    end
  end

  it "allows the same paid model once ALLOW_PAID_PROVIDERS=true" do
    with_env("IMAGE_PROVIDER" => "gemini", "IMAGE_MODEL" => "gemini-3-pro-image",
             "GEMINI_API_KEY" => "test-key", "ALLOW_PAID_PROVIDERS" => "true") do
      image = Providers.build_image
      expect(image).to be_a(Providers::CappedImageAdapter)
      expect(image.name).to eq("gemini")
    end
  end

  it "always builds the free Cloudflare image adapter" do
    with_env("IMAGE_PROVIDER" => "cloudflare", "IMAGE_MODEL" => nil, "ALLOW_PAID_PROVIDERS" => "false",
             "CLOUDFLARE_ACCOUNT_ID" => "acct", "CLOUDFLARE_API_TOKEN" => "tok") do
      expect(Providers.build_image).to be_a(Providers::Image::CloudflareAdapter)
    end
  end

  it "guards the voice registry too: free-tier TTS builds, pro TTS is refused" do
    with_env("VOICE_PROVIDER" => "gemini_tts", "GEMINI_API_KEY" => "test-key", "ALLOW_PAID_PROVIDERS" => "false") do
      expect { Providers.guard_paid!("voice", "gemini_tts", "gemini-2.5-flash-preview-tts") }.not_to raise_error
      expect { Providers.guard_paid!("voice", "gemini_tts", "gemini-2.5-pro-preview-tts") }
        .to raise_error(Providers::PaidProviderBlocked, /gemini-2\.5-pro-preview-tts/)
    end
  end

  it "guards the LLM registry: Anthropic is refused by default" do
    expect { Providers.guard_paid!("LLM", "anthropic", "claude-haiku-4-5") }
      .to raise_error(Providers::PaidProviderBlocked)
  end
end

RSpec.describe Providers::Voice::GeminiTtsAdapter, "cost from usage metadata" do
  around { |ex| with_key_tier("paid") { ex.run } }
  let(:adapter) { described_class.new(api_key: "test-key", model: "gemini-2.5-flash-preview-tts") }
  let(:url) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent" }

  before { allow_any_instance_of(described_class).to receive(:sleep) }

  def body_with_usage(seconds)
    samples = (seconds * described_class::SAMPLE_RATE).round
    pcm = (0...samples).map { |i| i.even? ? 12_000 : -12_000 }.pack("s<*")
    {
      responseId: "resp_cost",
      candidates: [ { content: { parts: [ { inlineData: { mimeType: "audio/L16;rate=24000", data: Base64.strict_encode64(pcm) } } ] } } ],
      usageMetadata: { promptTokenCount: 1_000, candidatesTokenCount: 4_000 }
    }.to_json
  end

  it "records real cost for a single synthesize call from promptTokenCount/candidatesTokenCount" do
    stub_request(:post, url).to_return(status: 200, body: body_with_usage(4.0), headers: { "Content-Type" => "application/json" })

    result = adapter.synthesize(text: "one two three four")

    expected = (1_000 * 0.50 + 4_000 * 10.00) / 1_000_000.0 # $0.0405
    expect(result.cost_usd).to be_within(1e-9).of(expected)
    expect(result.cost_usd).to be > 0
  end

  it "splits a batched chunk's cost across its scenes by word share, summing to the chunk total" do
    stub_request(:post, url).to_return(status: 200, body: body_with_usage(8.0), headers: { "Content-Type" => "application/json" })

    results = adapter.synthesize_batch(texts: [ "one two three", "four five" ])

    chunk_total = (1_000 * 0.50 + 4_000 * 10.00) / 1_000_000.0
    expect(results.map(&:cost_usd).sum).to be_within(1e-9).of(chunk_total)
    expect(results[0].cost_usd).to be > results[1].cost_usd # 3 words vs 2
  end
end

RSpec.describe Providers::CostReport do
  let(:project) { create(:project) }

  it "reports the actual total grouped by provider and kind" do
    AiGeneration.create!(project: project, kind: "image", provider: "gemini", model: "gemini-3-pro-image",
                         status: "succeeded", cost_usd: 0.134, request: {}, response: {})
    AiGeneration.create!(project: project, kind: "voice", provider: "gemini_tts", model: "gemini-2.5-flash-preview-tts",
                         status: "succeeded", cost_usd: 0.25, request: {}, response: {})

    actual = described_class.actual(project)

    expect(actual[:total_usd]).to eq(0.384)
    expect(actual[:by_stage].map { |r| [ r[:provider], r[:kind] ] }).to contain_exactly([ "gemini", "image" ], [ "gemini_tts", "voice" ])
  end

  it "surfaces a blocked paid provider in the estimate instead of raising" do
    saved = ENV.to_h.slice("IMAGE_PROVIDER", "IMAGE_MODEL", "ALLOW_PAID_PROVIDERS", "GEMINI_API_KEY")
    Providers.reset!
    ENV["IMAGE_PROVIDER"] = "gemini"
    ENV["IMAGE_MODEL"] = "gemini-3-pro-image"
    ENV["GEMINI_API_KEY"] = "test-key"
    ENV["ALLOW_PAID_PROVIDERS"] = "false"
    create(:scene, project: project, asset_strategy: "image")

    estimate = described_class.estimate(project)

    expect(estimate[:image][:blocked]).to match(/paid model/)
    expect(estimate[:image][:usd]).to be_nil
  ensure
    %w[IMAGE_PROVIDER IMAGE_MODEL ALLOW_PAID_PROVIDERS GEMINI_API_KEY].each { |k| ENV.delete(k) }
    saved.each { |k, v| ENV[k] = v }
    Providers.reset!
  end
end
