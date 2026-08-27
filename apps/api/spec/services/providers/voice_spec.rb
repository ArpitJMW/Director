require "rails_helper"

RSpec.describe Providers::Voice::FakeVoiceAdapter do
  it "returns a WAV whose length scales with the text" do
    short = described_class.new.synthesize(text: "Hi.")
    long = described_class.new.synthesize(text: "Word " * 60)

    expect(short.content_type).to eq("audio/wav")
    expect(short.audio_bytes[0, 4]).to eq("RIFF")
    expect(long.duration_seconds).to be > short.duration_seconds
  end

  it "produces per-character alignment covering the whole text" do
    result = described_class.new.synthesize(text: "abcdef")
    expect(result.alignment[:characters]).to eq(%w[a b c d e f])
    expect(result.alignment[:starts].length).to eq(6)
    expect(result.alignment[:ends].last).to be_within(0.01).of(result.duration_seconds)
  end
end

RSpec.describe Providers do
  it "picks the fake voice adapter without ELEVENLABS_API_KEY" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("VOICE_PROVIDER").and_return(nil)
    allow(ENV).to receive(:[]).with("ELEVENLABS_API_KEY").and_return(nil)

    described_class.reset!
    expect(described_class.build_voice).to be_a(Providers::Voice::FakeVoiceAdapter)
  ensure
    described_class.reset!
  end
end
