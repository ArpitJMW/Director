require "rails_helper"

RSpec.describe Providers::LLM::GeminiAdapter do
  subject(:adapter) { described_class.new(api_key: "test-key", model: "gemini-2.5-flash") }

  it "posts to generateContent and normalizes the response" do
    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*gemini-2\.5-flash:generateContent})
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          candidates: [ { content: { parts: [ { text: '{"hello":"world"}' } ] }, finishReason: "STOP" } ],
          usageMetadata: { promptTokenCount: 120, candidatesTokenCount: 40 },
          responseId: "resp_1"
        }.to_json
      )

    result = adapter.chat(system: "sys", messages: [ { role: "user", content: "hi" } ])

    expect(result.provider).to eq("gemini")
    expect(result.text).to eq('{"hello":"world"}')
    expect(result.input_tokens).to eq(120)
    expect(result.output_tokens).to eq(40)
  end

  it "raises a clear error on an HTTP failure" do
    stub_request(:post, /generativelanguage/).to_return(status: 429, body: "rate limited")
    expect { adapter.chat(system: "s", messages: [ { role: "user", content: "x" } ]) }
      .to raise_error(Providers::LLM::Base::Error, /429/)
  end

  it "requires an API key" do
    expect { described_class.new(api_key: nil) }.to raise_error(Providers::LLM::Base::Error, /GEMINI_API_KEY/)
  end
end

RSpec.describe Providers::Image::CloudflareAdapter do
  subject(:adapter) { described_class.new(account_id: "acc", api_token: "tok") }

  it "decodes a base64 image from the FLUX JSON response" do
    png = File.binread(Rails.root.join("spec/fixtures/files/sample.png"))
    stub_request(:post, %r{api\.cloudflare\.com/client/v4/accounts/acc/ai/run/})
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { result: { image: Base64.strict_encode64(png) }, success: true }.to_json
      )

    result = adapter.generate(prompt: "a fjord", aspect_ratio: "16:9")

    expect(result.provider).to eq("cloudflare")
    expect(result.content_type).to eq("image/jpeg")
    expect(result.bytes).to eq(png)
    expect(result.cost_usd).to eq(0.0)
  end

  it "raises on an HTTP error" do
    stub_request(:post, /api\.cloudflare\.com/).to_return(status: 401, body: "bad token")
    expect { adapter.generate(prompt: "x") }.to raise_error(Providers::Image::Base::Error, /401/)
  end
end

RSpec.describe Providers::Voice::EdgeTtsAdapter do
  subject(:adapter) { described_class.new }

  it "shells out and normalizes word-level alignment" do
    fake_status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(Open3).to receive(:capture3) do |*_args, stdin_data:|
      # the adapter passes the output path as the 4th arg
      out = _args[3]
      File.binwrite(out, "ID3fake-mp3-bytes")
      [ { duration: 2.4, words: [ { text: "Hello", start: 0.0, end: 0.5 } ] }.to_json, "", fake_status ]
    end

    result = adapter.synthesize(text: "Hello there")

    expect(result.provider).to eq("edge_tts")
    expect(result.content_type).to eq("audio/mpeg")
    expect(result.duration_seconds).to eq(2.4)
    expect(result.alignment[:words].first[:text]).to eq("Hello")
    expect(result.cost_usd).to eq(0.0)
  end

  it "raises when the helper script fails" do
    fail_status = instance_double(Process::Status, success?: false, exitstatus: 3)
    allow(Open3).to receive(:capture3).and_return([ "", "edge-tts not installed", fail_status ])

    expect { adapter.synthesize(text: "hi") }
      .to raise_error(Providers::Voice::Base::Error, /edge-tts not installed/)
  end
end

RSpec.describe Providers do
  around { |ex| described_class.reset!; ex.run; described_class.reset! }

  it "auto-selects gemini for LLM when only GEMINI_API_KEY is set" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LLM_PROVIDER").and_return(nil)
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
    allow(ENV).to receive(:[]).with("GEMINI_API_KEY").and_return("k")

    expect(described_class.build_llm).to be_a(Providers::LLM::GeminiAdapter)
  end

  it "auto-selects cloudflare for images when CLOUDFLARE_API_TOKEN is set" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("IMAGE_PROVIDER").and_return(nil)
    allow(ENV).to receive(:[]).with("CLOUDFLARE_API_TOKEN").and_return("t")
    allow(ENV).to receive(:[]).with("CLOUDFLARE_ACCOUNT_ID").and_return("a")

    expect(described_class.build_image).to be_a(Providers::Image::CloudflareAdapter)
  end

  it "selects edge_tts only when VOICE_PROVIDER asks for it" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("VOICE_PROVIDER").and_return("edge_tts")
    allow(ENV).to receive(:[]).with("ELEVENLABS_API_KEY").and_return(nil)

    expect(described_class.build_voice).to be_a(Providers::Voice::EdgeTtsAdapter)
  end
end

RSpec.describe Media::CaptionService, "with word-level alignment" do
  it "uses the words array directly (edge-tts shape)" do
    alignment = {
      words: [
        { text: "the", start: 0.0, end: 0.2 },
        { text: "quick", start: 0.2, end: 0.6 },
        { text: "brown", start: 0.6, end: 1.0 },
        { text: "fox", start: 1.0, end: 1.3 },
        { text: "jumps", start: 1.3, end: 1.8 },
        { text: "over", start: 1.8, end: 2.2 },
        { text: "it", start: 2.2, end: 2.4 },
        { text: "again", start: 2.4, end: 2.9 }
      ]
    }
    cues = described_class.build(text: "the quick brown fox jumps over it again", alignment: alignment)

    expect(cues.length).to be >= 2
    expect(cues.first[:start]).to eq(0.0)
    expect(cues.map { |c| c[:text] }.join(" ").split.length).to eq(8)
  end
end
