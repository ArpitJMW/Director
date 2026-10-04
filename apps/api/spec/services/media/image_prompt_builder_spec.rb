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

  it "keeps negative constraints out of the positive prompt" do
    scene.update!(negative_prompt: "savanna, daytime")
    expect(built[:prompt]).not_to include("savanna")
    expect(built[:negative_prompt]).to include("savanna")
  end

  it "hard-anchors the planner subject at the front of the prompt" do
    scene.update!(visual_prompt: "close-up of an eye and skin folds",
      metadata: { "subject" => "an Asian elephant calf" })
    expect(built[:prompt]).to start_with("an Asian elephant calf.")
  end

  it "builds a shot-specific prompt when given a shot" do
    scene.update!(metadata: { "subject" => "a Bengal tiger", "environment" => "mangrove forest" })
    shot = scene.shots.create!(position: 1, duration_seconds: 4, shot_type: "close_up",
      visual_prompt: "the tiger's eyes catching the light")
    out = described_class.new(scene: scene, shot: shot, project: project).call
    expect(out[:prompt]).to include("the tiger's eyes catching the light")
    expect(out[:prompt]).to include("close up")
  end

  it "produces a stable per-project seed" do
    first = described_class.new(scene: scene, project: project).call[:seed]
    other = create(:scene, project: project, position: 2, key: "scene_02")
    second = described_class.new(scene: other, project: project.reload).call[:seed]

    expect(first).to eq(second)
    expect(project.reload.image_seed).to eq(first)
  end

  it "prefixes the project niche as the subject when the planner gave none" do
    scene.update!(visual_prompt: "a wide shot of the forest canopy", metadata: {})
    expect(built[:prompt]).to start_with("wildlife documentary.")
  end

  it "falls back to the cinematic style for an unknown value" do
    project.update_column(:visual_style, "nonsense")
    expect(built[:prompt]).to include("anamorphic lens")
  end

  describe "Task 2.5 — safety, no-text and action fidelity" do
    it "always includes the fixed safety clause in the positive prompt (FLUX drops negative_prompt)" do
      expect(built[:prompt]).to include("fully clothed").and include("no nudity")
    end

    it "always includes the fixed no-text clause in the positive prompt" do
      expect(built[:prompt]).to include("no readable text").and include("no signage")
    end

    it "also appends the safety concepts to negative_prompt, for providers that do honour it" do
      expect(built[:negative_prompt]).to include("nudity").and include("gore")
    end

    it "puts the scene's action right after the subject, before the planner's own free-text brief" do
      scene.update!(
        action: "the tiger pounces into shallow water, spraying droplets",
        visual_prompt: "an adult male Bengal tiger at a river bank, dawn light, low angle",
        metadata: { "subject" => "a Bengal tiger" }
      )

      prompt = described_class.new(scene: scene, project: project).call[:prompt]
      subject_pos = prompt.index("Bengal tiger")
      action_pos = prompt.index("pounces into shallow water")
      brief_pos = prompt.index("river bank, dawn light")

      expect(action_pos).to be_present
      expect(action_pos).to be < brief_pos
      expect(subject_pos).to be <= action_pos
    end

    it "uses the shot's own action (not the parent scene's) when given a shot" do
      scene.update!(action: "scene-level action", metadata: { "subject" => "a Bengal tiger" })
      shot = scene.shots.create!(position: 1, duration_seconds: 4, shot_type: "close_up",
        action: "shot-level action: the tiger's eye narrows", visual_prompt: "close framing on the eye")

      prompt = described_class.new(scene: scene, shot: shot, project: project).call[:prompt]
      expect(prompt).to include("shot-level action")
      expect(prompt).not_to include("scene-level action")
    end
  end
end
