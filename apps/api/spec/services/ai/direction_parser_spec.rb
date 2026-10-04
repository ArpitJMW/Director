require "rails_helper"

RSpec.describe Ai::DirectionParser do
  let(:project) { create(:project) }
  let(:parser) { described_class.new(project: project, unit_key: "scene_01") }

  it "returns an empty hash for nil/absent direction, with no log" do
    expect(parser.parse(nil)).to eq({})
    expect(project.generation_logs).to be_empty
  end

  it "passes through every valid field" do
    result = parser.parse(
      "camera_motion" => "drift", "camera_intensity" => "high", "transition_in" => "wipe",
      "overlay" => { "type" => "title_card", "text" => "Chapter One" },
      "text_style" => "quote", "items" => %w[a b], "number" => 42, "unit" => "%",
      "direction_reason" => "because"
    )

    expect(result).to eq(
      transition: "wipe", camera_movement: "drift", intensity: "high",
      overlay: { "type" => "title_card", "text" => "Chapter One" },
      text_style: "quote", items: %w[a b], number: 42, unit: "%", direction_reason: "because"
    )
  end

  it "omits (never defaults) a field the LLM simply didn't set" do
    result = parser.parse("camera_motion" => "drift")
    expect(result).to eq(camera_movement: "drift")
    expect(project.generation_logs).to be_empty
  end

  %w[camera_motion transition_in].each do |field|
    it "falls back to nil and logs a warning for an invalid #{field}" do
      result = parser.parse(field => "not_a_real_value")
      expect(result).to eq({})
      log = project.generation_logs.where(level: "warn", stage: "direction").last
      expect(log.message).to include("scene_01").and include(field).and include("not_a_real_value")
    end
  end

  it "drops overlay entirely when type is invalid, and logs" do
    result = parser.parse("overlay" => { "type" => "confetti", "text" => "x" })
    expect(result[:overlay]).to be_nil
    expect(project.generation_logs.where(level: "warn", stage: "direction")).to be_present
  end

  it "treats an explicit overlay type of 'none' as no overlay, without logging" do
    result = parser.parse("overlay" => { "type" => "none" })
    expect(result[:overlay]).to be_nil
    expect(project.generation_logs).to be_empty
  end

  it "caps items at 6 and strips blanks" do
    result = parser.parse("items" => [ "a", "", "  b  ", "c", "d", "e", "f", "g" ])
    expect(result[:items]).to eq(%w[a b c d e f])
  end
end
