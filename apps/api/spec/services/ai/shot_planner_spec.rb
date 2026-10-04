require "rails_helper"

RSpec.describe Ai::ShotPlanner do
  let(:project) { create(:project, visual_style: "wildlife_documentary") }
  let(:scene) do
    create(:scene, project: project, duration_seconds: 10, visual_type: "image",
      visual_prompt: "an Asian elephant calf in a misty forest clearing",
      purpose: "the calf gets separated",
      metadata: { "subject" => "an Asian elephant calf", "environment" => "misty tropical forest" })
  end

  it "creates ordered shots whose durations sum to the scene duration" do
    shots = described_class.new(scene: scene).call

    expect(shots.size).to be_between(1, described_class::MAX_SHOTS)
    expect(scene.reload.shots.pluck(:position)).to eq((1..shots.size).to_a)
    expect(scene.shots.sum(&:duration_seconds).to_f).to be_within(0.6).of(10.0)
  end

  it "carries the scene visual_type and content onto each shot" do
    described_class.new(scene: scene).call
    expect(scene.reload.shots.pluck(:visual_type).uniq).to eq([ "image" ])
  end

  it "carries the scene's asset_strategy onto each shot" do
    described_class.new(scene: scene).call
    expect(scene.reload.shots.pluck(:asset_strategy).uniq).to eq([ "image" ])
  end

  it "plans shots for a scene labeled a non-image visual_type as long as asset_strategy is image " \
     "(Task 2.3 — asset_strategy gates planning, not visual_type)" do
    chart_as_image = create(:scene, project: project, duration_seconds: 10,
      visual_type: "chart", asset_strategy: "image",
      visual_prompt: "a bar chart comparing yearly and monthly compounding")

    shots = described_class.new(scene: chart_as_image).call

    expect(shots).not_to be_empty
    expect(chart_as_image.reload.shots.pluck(:asset_strategy).uniq).to eq([ "image" ])
  end

  it "replaces shots on a re-run" do
    described_class.new(scene: scene).call
    first_ids = scene.reload.shots.pluck(:id)
    described_class.new(scene: scene.reload).call
    expect(scene.reload.shots.pluck(:id) & first_ids).to be_empty
  end

  it "records a shot_plan ai_generation" do
    described_class.new(scene: scene).call
    expect(project.ai_generations.where(kind: "shot_plan").last.status).to eq("succeeded")
  end

  it "skips scenes whose asset_strategy is not image, regardless of visual_type" do
    text_scene = create(:scene, project: project, duration_seconds: 10,
      visual_type: "text_animation", asset_strategy: "text",
      visual_prompt: "a text card so this isn't skipped for lack of a prompt")

    expect(described_class.new(scene: text_scene).call).to eq([])
    expect(text_scene.reload.shots).to be_empty
  end

  it "skips a scene with no visual_prompt even when asset_strategy is image" do
    blank = create(:scene, project: project, visual_type: "image", asset_strategy: "image", visual_prompt: nil)
    expect(described_class.new(scene: blank).call).to eq([])
    expect(blank.reload.shots).to be_empty
  end

  describe "direction (Phase 1 Task 4)" do
    def stub_provider(shot_overrides)
      fake = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      base = {
        duration_seconds: 5, shot_type: "medium", camera_movement: "pan_right",
        framing: "close", action: "a detail of the moment",
        visual_prompt: "close framing", negative_prompt: ""
      }.merge(shot_overrides)
      json = { scenes: [ { key: scene.key, shots: [ base ] } ] }.to_json
      allow(fake).to receive(:chat).and_return(
        Providers::LLM::Result.new(
          text: json, model: "fake-1", provider: "fake", stop_reason: "end_turn",
          usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil
        )
      )
      fake
    end

    it "prefers direction.camera_motion over the legacy camera_movement field" do
      provider = stub_provider(direction: { camera_motion: "drift", camera_intensity: "low", direction_reason: "calm beat" })
      described_class.new(scene: scene, provider: provider).call

      shot = scene.reload.shots.first
      expect(shot.camera_movement).to eq("drift")
      expect(shot.motion["intensity"]).to eq("low")
      expect(shot.metadata["direction_reason"]).to eq("calm beat")
    end

    it "falls back to legacy camera_movement when direction is absent" do
      provider = stub_provider({})
      described_class.new(scene: scene, provider: provider).call

      expect(scene.reload.shots.first.camera_movement).to eq("pan_right")
    end

    it "applies a valid overlay and logs nothing" do
      provider = stub_provider(direction: { overlay: { type: "stat_callout", value: "42%", text: "of failures" } })
      described_class.new(scene: scene, provider: provider).call

      shot = scene.reload.shots.first
      expect(shot.metadata["overlay"]).to eq("type" => "stat_callout", "value" => "42%", "text" => "of failures")
      expect(project.generation_logs.where(stage: "direction")).to be_empty
    end

    it "falls back and logs a warning for an invalid camera_motion" do
      provider = stub_provider(direction: { camera_motion: "spin_360" })
      described_class.new(scene: scene, provider: provider).call

      shot = scene.reload.shots.first
      expect(shot.camera_movement).to eq("pan_right") # legacy field still used as fallback
      log = project.generation_logs.where(level: "warn", stage: "direction").last
      expect(log.message).to include("spin_360")
    end
  end
end
