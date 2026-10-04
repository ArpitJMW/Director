require "rails_helper"

RSpec.describe Prompts do
  it "loads the highest version of a stage prompt" do
    tpl = described_class.load("scene_planner")
    expect(tpl.name).to eq("scene_planner")
    expect(tpl.version).to be >= 1
    expect(tpl.text).to include("You are the scene planner")
  end

  it "raises for an unknown stage" do
    expect { described_class.load("nope") }.to raise_error(ArgumentError)
  end

  it "picks scene_planner v8 (Task 7.1 compact rewrite) as the current default" do
    tpl = described_class.load("scene_planner")
    expect(tpl.version).to eq(8)
    expect(tpl.text).to include("visual_reason").and include("SAFETY").and include("nude")
    expect(tpl.text).to include("TEXT-BEARING OBJECTS").and include("map")
    expect(tpl.text).to include("DIRECTION").and include("camera_motion").and include("text_style")
    expect(tpl.text).to include("{camera_motions}").and include("{overlay_types}").and include("{text_styles}")
    expect(tpl.text).to include("NAMED SUBJECTS").and include("nameplate").and include("REQUIRED")
    expect(tpl.text).to include("micro")
  end

  it "keeps scene_planner v7 intact and pinnable" do
    tpl = described_class.load("scene_planner", version: 7)
    expect(tpl.version).to eq(7)
    expect(tpl.text).to include("micro-scenes")
  end

  it "keeps scene_planner v6 intact and pinnable" do
    tpl = described_class.load("scene_planner", version: 6)
    expect(tpl.version).to eq(6)
    expect(tpl.text).not_to include("micro-scenes")
  end

  it "keeps scene_planner v5 intact and pinnable" do
    tpl = described_class.load("scene_planner", version: 5)
    expect(tpl.version).to eq(5)
    expect(tpl.text).not_to include("NAMED SUBJECTS")
  end

  it "keeps scene_planner v4 intact and pinnable" do
    tpl = described_class.load("scene_planner", version: 4)
    expect(tpl.version).to eq(4)
    expect(tpl.text).not_to include("DIRECTION — YOU ARE THE DIRECTOR")
  end

  it "keeps scene_planner v3 intact and pinnable" do
    tpl = described_class.load("scene_planner", version: 3)
    expect(tpl.version).to eq(3)
    expect(tpl.text).not_to include("SUBJECT RULES")
  end

  it "keeps scene_planner v2 intact and pinnable" do
    tpl = described_class.load("scene_planner", version: 2)
    expect(tpl.version).to eq(2)
    expect(tpl.text).not_to include("SAFETY & CONTENT RULES")
  end

  it "keeps scene_planner v1 intact and pinnable" do
    tpl = described_class.load("scene_planner", version: 1)
    expect(tpl.version).to eq(1)
    expect(tpl.text).not_to include("visual_reason")
  end

  it "picks shot_planner v5 (Task 4.3's named-subjects-to-overlay prompt) as the current default" do
    tpl = described_class.load("shot_planner")
    expect(tpl.version).to eq(5)
    expect(tpl.text).to include("SAFETY & CONTENT RULES")
    expect(tpl.text).to include("SUBJECT RULES").and include("map")
    expect(tpl.text).to include("fire or burning")
    expect(tpl.text).to include("DIRECTION").and include("camera_motion").and include("overlay")
    expect(tpl.text).to include("NAMED SUBJECTS").and include("nameplate")
  end

  it "keeps shot_planner v4 intact and pinnable" do
    tpl = described_class.load("shot_planner", version: 4)
    expect(tpl.version).to eq(4)
    expect(tpl.text).not_to include("NAMED SUBJECTS")
  end

  it "keeps shot_planner v3 intact and pinnable" do
    tpl = described_class.load("shot_planner", version: 3)
    expect(tpl.version).to eq(3)
    expect(tpl.text).not_to include("DIRECTION — CAMERA + OVERLAY")
  end

  it "keeps shot_planner v2 intact and pinnable" do
    tpl = described_class.load("shot_planner", version: 2)
    expect(tpl.version).to eq(2)
    expect(tpl.text).not_to include("SUBJECT RULES")
  end

  it "keeps shot_planner v1 intact and pinnable" do
    tpl = described_class.load("shot_planner", version: 1)
    expect(tpl.version).to eq(1)
    expect(tpl.text).not_to include("SAFETY & CONTENT RULES")
  end

  it "every referenced stage prompt exists" do
    %w[script scene_planner shot_planner].each do |name|
      expect { described_class.load(name) }.not_to raise_error
    end
  end
end
