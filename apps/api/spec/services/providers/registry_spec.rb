require "rails_helper"

RSpec.describe Providers do
  around do |example|
    described_class.reset!
    example.run
    described_class.reset!
  end

  it "uses the fake adapter when no API key is configured" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LLM_PROVIDER").and_return(nil)
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)

    expect(described_class.build_llm).to be_a(Providers::LLM::FakeAdapter)
  end

  it "honours an explicit LLM_PROVIDER=fake" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LLM_PROVIDER").and_return("fake")

    expect(described_class.build_llm.name).to eq("fake")
  end

  it "raises on an unknown provider" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LLM_PROVIDER").and_return("bogus")

    expect { described_class.build_llm }.to raise_error(ArgumentError, /bogus/)
  end
end

RSpec.describe Providers::LLM::FakeAdapter do
  it "returns a parseable script JSON payload with usage" do
    result = described_class.new.chat(
      system: "sys", messages: [ { role: "user", content: "Topic: black holes" } ]
    )

    expect(result.provider).to eq("fake")
    expect(result.total_tokens).to be > 0
    data = JSON.parse(result.text)
    expect(data["title_options"]).to be_an(Array)
    expect(data["full_narration"]).to include("black holes")
  end
end
