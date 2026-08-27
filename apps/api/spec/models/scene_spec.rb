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

  describe "#to_scene_json (spec §19 contract)" do
    it "produces the agreed shape with the selected asset's public id" do
      asset = create(:asset, project: project)
      scene = create(:scene, project: project, selected_asset: asset,
        narration: "N", caption: "C", background_music_level: 0.2)

      json = scene.to_scene_json
      expect(json.keys).to contain_exactly(
        :id, :duration, :narration, :visual_type, :visual_prompt,
        :asset_id, :caption, :animation, :transition, :background_music_level
      )
      expect(json[:id]).to eq(scene.key)
      expect(json[:asset_id]).to eq(asset.public_id)
      expect(json[:duration]).to be_a(Float)
      expect(json[:background_music_level]).to eq(0.2)
    end
  end

  it "rejects an unknown visual_type" do
    expect(build(:scene, project: project, visual_type: "hologram")).not_to be_valid
  end
end
