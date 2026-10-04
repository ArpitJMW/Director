require "rails_helper"

RSpec.describe Providers::PaidImageCap do
  around do |example|
    saved = ENV["PAID_IMAGE_CALL_CAP"]
    Providers::PaidImageCap.reset!
    example.run
  ensure
    saved.nil? ? ENV.delete("PAID_IMAGE_CALL_CAP") : ENV["PAID_IMAGE_CALL_CAP"] = saved
    Providers::PaidImageCap.reset!
  end

  it "defaults to a cap of 0, so a paid image call is refused" do
    ENV.delete("PAID_IMAGE_CALL_CAP")
    expect { described_class.reserve!(provider: "gemini", model: "gemini-3.1-flash-image") }
      .to raise_error(described_class::Exhausted, /cap reached \(0\/0\)/)
  end

  it "allows exactly the capped number of calls, and refuses the next one" do
    ENV["PAID_IMAGE_CALL_CAP"] = "2"
    2.times { described_class.reserve!(provider: "gemini", model: "gemini-3.1-flash-image") }

    expect { described_class.reserve!(provider: "gemini", model: "gemini-3.1-flash-image") }
      .to raise_error(described_class::Exhausted)
    expect(described_class.used).to eq(2)
  end

  it "wraps a paid image adapter so the 9th call is refused at the registry" do
    ENV["PAID_IMAGE_CALL_CAP"] = "8"
    adapter = double("gemini", name: "gemini", default_model: "gemini-3.1-flash-image")
    allow(adapter).to receive(:generate).and_return(:ok)
    capped = Providers::CappedImageAdapter.new(adapter)

    8.times { capped.generate(prompt: "x") }
    expect { capped.generate(prompt: "x") }.to raise_error(described_class::Exhausted)
    expect(adapter).to have_received(:generate).exactly(8).times
  end

  it "never caps a free image adapter" do
    ENV["PAID_IMAGE_CALL_CAP"] = "0"
    adapter = double("cloudflare", name: "cloudflare", default_model: "@cf/black-forest-labs/flux-1-schnell")
    allow(adapter).to receive(:generate).and_return(:ok)

    ENV["ALLOW_PAID_PROVIDERS"] = "false"
    Providers.reset!
    Providers.image = adapter
    expect(Providers.image).to eq(adapter)
    expect(Providers.image.generate(prompt: "x")).to eq(:ok)
  ensure
    Providers.reset!
  end
end
