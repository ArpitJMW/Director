require "rails_helper"

RSpec.describe Ai::DurationHint do
  it "reads a range and takes the midpoint" do
    expect(described_class.parse("Create a 30-40 second cinematic video")).to eq(35)
  end

  it "reads a single value in seconds" do
    expect(described_class.parse("about 45 seconds long")).to eq(45)
  end

  it "reads minutes" do
    expect(described_class.parse("a two? no — make it 3 minute documentary")).to eq(180)
  end

  it "returns nil when there is no length" do
    expect(described_class.parse("a video about elephants in the forest")).to be_nil
  end

  it "ignores out-of-range values" do
    expect(described_class.parse("the 100 m sprint world record")).to be_nil
  end

  it "handles nils" do
    expect(described_class.parse(nil, nil)).to be_nil
  end
end
