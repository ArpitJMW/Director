require "rails_helper"

RSpec.describe Media::ImagePromptBuilder do
  let(:project) do
    create(:project, niche: "wildlife documentary", visual_style: "wildlife_documentary")
  end
  let(:scene) do
    create(:scene, project: project,
      visual_prompt: "an adult male Bengal tiger walking along a river bank at dawn, low angle")
  end

  subject(:built) { described_class.new(scene: scene, project: project).call }

  it "wraps the scene prompt with the project's visual style" do
    expect(built[:prompt]).to include("adult male Bengal tiger")
    expect(built[:prompt]).to include("telephoto lens")
    expect(built[:prompt]).to include("photorealistic")
  end

  it "returns an avoid/negative clause" do
    expect(built[:negative_prompt]).to include("text", "watermark")
  end

  it "produces a stable per-project seed" do
    first = described_class.new(scene: scene, project: project).call[:seed]
    other = create(:scene, project: project, position: 2, key: "scene_02")
    second = described_class.new(scene: other, project: project.reload).call[:seed]

    expect(first).to eq(second)
    expect(project.reload.image_seed).to eq(first)
  end

  it "prefixes the niche as subject context when missing from the prompt" do
    scene.update!(visual_prompt: "a wide shot of the forest canopy")
    expect(built[:prompt]).to start_with("wildlife documentary:")
  end

  it "falls back to the cinematic style for an unknown value" do
    project.update_column(:visual_style, "nonsense")
    expect(built[:prompt]).to include("anamorphic lens")
  end
end
