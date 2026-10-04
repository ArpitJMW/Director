require "rails_helper"

RSpec.describe Scene, type: :model do
  let(:project) { create(:project) }

  it "auto-assigns sequential position and key" do
    a = create(:scene, project: project)
    b = create(:scene, project: project)

    expect(a.position).to eq(1)
    expect(a.key).to eq("scene_01")
    expect(b.position).to eq(2)
    expect(b.key).to eq("scene_02")
  end

  it "enforces unique position per project" do
    create(:scene, project: project, position: 1)
    dup = build(:scene, project: project, position: 1)
    expect(dup).not_to be_valid
  end

  describe "#to_scene_json (spec §19 + planning-doc §6 contract)" do
    it "produces the base shape with the selected asset's public id" do
      asset = create(:asset, project: project)
      scene = create(:scene, project: project, selected_asset: asset,
        narration: "N", caption: "C", background_music_level: 0.2)

      json = scene.to_scene_json
      # base contract + asset_strategy (always present, defaults to "image")
      expect(json.keys).to contain_exactly(
        :id, :duration, :narration, :visual_type, :visual_prompt,
        :asset_id, :caption, :animation, :transition, :background_music_level,
        :asset_strategy
      )
      expect(json[:id]).to eq(scene.key)
      expect(json[:asset_id]).to eq(asset.public_id)
      expect(json[:duration]).to be_a(Float)
      expect(json[:background_music_level]).to eq(0.2)
      expect(json[:asset_strategy]).to eq("image")
      expect(json).not_to have_key(:shots)
    end

    it "emits direction fields only when set" do
      scene = create(:scene, project: project, purpose: "hook",
        action: "tiger walks through water", mood: "tense",
        camera: { "shot_type" => "low_angle_tracking" })

      json = scene.to_scene_json
      expect(json[:purpose]).to eq("hook")
      expect(json[:action]).to eq("tiger walks through water")
      expect(json[:mood]).to eq("tense")
      expect(json[:camera]).to eq({ "shot_type" => "low_angle_tracking" })
      expect(json).not_to have_key(:content_type) # unset -> omitted
    end

    it "emits production_method / text_spec only once a Media::ProductionDispatcher-routed service sets them" do
      scene = create(:scene, project: project)
      expect(scene.to_scene_json).not_to have_key(:production_method)
      expect(scene.to_scene_json).not_to have_key(:text_spec)

      scene.update!(metadata: { "production_method" => "text", "text_spec" => { "lines" => [ "Hi" ] } })
      json = scene.to_scene_json
      expect(json[:production_method]).to eq("text")
      expect(json[:text_spec]).to eq({ "lines" => [ "Hi" ] })
    end

    it "includes shots in order when the scene has them" do
      scene = create(:scene, project: project)
      shot_b = scene.shots.create!(position: 2, duration_seconds: 3, shot_type: "close_up")
      shot_a = scene.shots.create!(position: 1, duration_seconds: 4, shot_type: "wide")

      json = scene.to_scene_json
      expect(json[:shots].map { |s| s[:id] }).to eq([ shot_a.key, shot_b.key ])
      expect(json[:shots].first).to include(id: shot_a.key, duration: 4.0, shot_type: "wide")
    end
  end

  it "rejects an unknown visual_type" do
    expect(build(:scene, project: project, visual_type: "hologram")).not_to be_valid
  end
end
