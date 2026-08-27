require "rails_helper"

RSpec.describe Providers::Image::FakeImageAdapter do
  it "returns a valid PNG at the requested aspect ratio" do
    result = described_class.new.generate(prompt: "a volcano at dusk", aspect_ratio: "16:9")

    expect(result.content_type).to eq("image/png")
    expect(result.provider).to eq("fake")
    expect(FastImage.size(StringIO.new(result.bytes))).to eq([ 1280, 720 ])
    expect(FastImage.type(StringIO.new(result.bytes))).to eq(:png)
  end

  it "is deterministic for the same prompt" do
    a = described_class.new.generate(prompt: "same", aspect_ratio: "1:1")
    b = described_class.new.generate(prompt: "same", aspect_ratio: "1:1")
    expect(a.bytes).to eq(b.bytes)
  end

  it "renders 9:16 for shorts" do
    result = described_class.new.generate(prompt: "x", aspect_ratio: "9:16")
    expect(FastImage.size(StringIO.new(result.bytes))).to eq([ 720, 1280 ])
  end
end

RSpec.describe Providers do
  it "picks the fake image adapter when GEMINI_API_KEY is absent" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("IMAGE_PROVIDER").and_return(nil)
    allow(ENV).to receive(:[]).with("GEMINI_API_KEY").and_return(nil)

    described_class.reset!
    expect(described_class.build_image).to be_a(Providers::Image::FakeImageAdapter)
  ensure
    described_class.reset!
  end
end
