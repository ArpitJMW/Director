require "rails_helper"

RSpec.describe Shot, type: :model do
  let(:scene) { create(:scene) }

  it "auto-assigns sequential position and a scene-scoped key" do
    a = create(:shot, scene: scene)
    b = create(:shot, scene: scene)

    expect(a.position).to eq(1)
    expect(a.key).to eq("#{scene.key}_shot_1")
    expect(b.position).to eq(2)
  end

  it "enforces unique position per scene" do
    create(:shot, scene: scene, position: 1)
    expect(build(:shot, scene: scene, position: 1)).not_to be_valid
  end

  it "rejects an unknown visual_type" do
    expect(build(:shot, scene: scene, visual_type: "hologram")).not_to be_valid
  end

  it "is torn down with its scene without leaving orphan assets" do
    asset = create(:asset, project: scene.project, scene: scene)
    create(:shot, scene: scene, selected_asset: asset)

    expect { scene.destroy }.to change(Shot, :count).by(-1)
    expect(Asset.exists?(asset.id)).to be(false)
  end

  it "exposes a flat render contract" do
    shot = create(:shot, scene: scene, shot_type: "wide", camera_movement: "push_in",
      duration_seconds: 5)
    expect(shot.to_shot_json).to include(
      id: shot.key, duration: 5.0, shot_type: "wide", camera_movement: "push_in",
      visual_type: "image"
    )
  end
end
