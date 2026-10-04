require "rails_helper"

RSpec.describe Ai::ScenePlannerService do
  let(:project) { create(:project, topic: "Deep sea vents", target_duration_seconds: 90) }

  before { Ai::ScriptService.new(project: project).call }

  it "creates ordered scenes following the §19 contract" do
    scenes = described_class.new(project: project).call

    expect(scenes.size).to be >= 2
    expect(project.reload.scenes.pluck(:position)).to eq((1..scenes.size).to_a)
    expect(project.scenes.pluck(:key)).to eq(scenes.each_index.map { |i| format("scene_%02d", i + 1) })

    first = project.scenes.first
    expect(Scene::VISUAL_TYPES).to include(first.visual_type)
    expect(first.to_scene_json.keys).to include(:id, :duration, :visual_type, :animation, :transition)
  end

  it "varies the visual treatment (not one image per scene)" do
    described_class.new(project: project).call
    expect(project.reload.scenes.pluck(:visual_type).uniq.size).to be > 1
  end

  it "replaces existing scenes on regeneration" do
    described_class.new(project: project).call
    original_ids = project.reload.scenes.pluck(:id)

    described_class.new(project: project).call
    expect(project.reload.scenes.pluck(:id) & original_ids).to be_empty
  end

  it "records a scene_plan ai_generation with the prompt version" do
    described_class.new(project: project).call
    gen = project.ai_generations.where(kind: "scene_plan").last
    expect(gen.status).to eq("succeeded")
    expect(gen.request["prompt_version"]).to be >= 1
  end

  it "persists production direction on each scene" do
    described_class.new(project: project).call
    scene = project.reload.scenes.find_by(visual_type: "image")

    expect(scene.purpose).to be_present
    expect(scene.action).to be_present
    expect(scene.mood).to be_present
    expect(scene.camera).to include("shot_type")
    expect(scene.negative_prompt).to be_present
    expect(scene.metadata["subject"]).to be_present
    expect(scene.metadata["environment"]).to be_present
  end

  it "carries subject and environment into to_scene_json direction fields" do
    described_class.new(project: project).call
    json = project.reload.scenes.find_by(visual_type: "image").to_scene_json
    expect(json).to include(:purpose, :action, :mood, :camera, :asset_strategy)
  end

  it "raises when there is no current script" do
    project.scripts.update_all(current: false)
    expect { described_class.new(project: project.reload).call }
      .to raise_error(Ai::ScenePlannerService::Error, /no current script/)
  end

  describe "visual_reason (scene_planner prompt v2, Task 2.2)" do
    def stub_provider(scene_overrides)
      fake = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      base = {
        purpose: "state the stat", narration: "Half of it fails.", caption: "Half fails",
        duration_seconds: 5, content_type: "documentary", visual_type: "text_animation",
        asset_strategy: "text", subject: "the subject", environment: "an office",
        action: "n/a", camera: {}, mood: "serious", visual_prompt: "a text card",
        negative_prompt: "", animation: "text_reveal", transition: "fade",
        background_music_level: 0.15
      }.merge(scene_overrides)
      json = { scenes: [ base ] }.to_json
      allow(fake).to receive(:chat).and_return(
        Providers::LLM::Result.new(
          text: json, model: "fake-1", provider: "fake", stop_reason: "end_turn",
          usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil
        )
      )
      fake
    end

    it "stores visual_reason in scene metadata when the provider includes it" do
      provider = stub_provider(visual_reason: "the whole beat is one statistic")
      described_class.new(project: project, provider: provider).call

      expect(project.reload.scenes.first.metadata["visual_reason"]).to eq("the whole beat is one statistic")
    end

    it "still works when the provider output has no visual_reason (v1-style plan)" do
      provider = stub_provider({})
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene).to be_persisted
      expect(scene.metadata).not_to have_key("visual_reason")
    end
  end

  describe "scene timing (Task 7.2 Part C)" do
    # The model's per-scene seconds are ignored when narration exists: each scene
    # takes its share of the target by narration word count, so the plan totals
    # the target instead of whatever the model guessed (a 24s plan for 45s).
    def stub_scenes(scenes)
      fake = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      base = { purpose: "p", caption: "c", content_type: "documentary", visual_type: "text_animation",
               asset_strategy: "text", subject: "s", environment: "e", action: "n/a", camera: {},
               mood: "m", visual_prompt: "v", negative_prompt: "", animation: "text_reveal", transition: "fade",
               background_music_level: 0.15 }
      json = { scenes: scenes.map { |s| base.merge(s) } }.to_json
      allow(fake).to receive(:chat).and_return(
        Providers::LLM::Result.new(text: json, model: "fake-1", provider: "fake", stop_reason: "end_turn",
                                   usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil)
      )
      fake
    end

    it "splits the target across scenes by narration length, ignoring the model's seconds" do
      project.update!(target_duration_seconds: 45)
      provider = stub_scenes([
        { narration: "one two three", duration_seconds: 20 },
        { narration: "one two three three more words", duration_seconds: 2 }
      ])
      described_class.new(project: project, provider: provider).call

      durations = project.reload.scenes.order(:position).pluck(:duration_seconds).map(&:to_f)
      expect(durations).to eq([ 15.0, 30.0 ])
      expect(durations.sum).to eq(45.0)
    end

    it "falls back to the model's seconds when no scene has narration" do
      project.update!(target_duration_seconds: 45)
      provider = stub_scenes([ { narration: "", duration_seconds: 7 } ])
      described_class.new(project: project, provider: provider).call

      expect(project.reload.scenes.first.duration_seconds.to_f).to eq(7.0)
    end
  end

  describe "direction (Phase 1 Task 4)" do
    def stub_provider(scene_overrides)
      fake = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      base = {
        purpose: "show the press", narration: "The press stamps letters.", caption: "The press",
        duration_seconds: 5, content_type: "cinematic", visual_type: "image",
        asset_strategy: "image", subject: "a press", environment: "a workshop",
        action: "the press stamps letters", camera: {}, mood: "inventive",
        visual_prompt: "a press", negative_prompt: "", animation: "ken_burns",
        background_music_level: 0.15
      }.merge(scene_overrides)
      json = { scenes: [ base ] }.to_json
      allow(fake).to receive(:chat).and_return(
        Providers::LLM::Result.new(
          text: json, model: "fake-1", provider: "fake", stop_reason: "end_turn",
          usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil
        )
      )
      fake
    end

    it "applies a valid direction: camera into camera/motion, transition, overlay and reason into metadata" do
      provider = stub_provider(direction: {
        camera_motion: "drift", camera_intensity: "high", transition_in: "crossfade",
        overlay: { type: "lower_third", text: "Gutenberg's workshop" },
        direction_reason: "a reflective beat"
      })
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene.camera["movement"]).to eq("drift")
      expect(scene.motion["intensity"]).to eq("high")
      expect(scene.transition).to eq("crossfade")
      expect(scene.metadata["overlay"]).to eq("type" => "lower_third", "text" => "Gutenberg's workshop")
      expect(scene.metadata["direction_reason"]).to eq("a reflective beat")
    end

    it "applies text_style/items to a text unit's direction_text metadata" do
      provider = stub_provider(
        visual_type: "text_animation", asset_strategy: "text",
        direction: { text_style: "list_reveal", items: %w[Venice Paris Mainz], direction_reason: "a place list" }
      )
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene.metadata["direction_text"]).to eq("text_style" => "list_reveal", "items" => %w[Venice Paris Mainz])
    end

    it "falls back and logs a warning for an invalid camera_motion instead of failing or silently guessing" do
      provider = stub_provider(direction: { camera_motion: "vertigo_spin" })
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene.camera["movement"]).to be_nil
      log = project.generation_logs.where(level: "warn", stage: "direction").last
      expect(log).to be_present
      expect(log.message).to include("vertigo_spin")
    end

    it "falls back and logs a warning for an invalid transition_in" do
      provider = stub_provider(direction: { transition_in: "teleport" })
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene.transition).to eq("fade") # legacy default fallback, not the invalid value
      log = project.generation_logs.where(level: "warn", stage: "direction").last
      expect(log.message).to include("teleport")
    end

    it "drops an invalid overlay type and logs, without touching the rest of the scene" do
      provider = stub_provider(direction: { overlay: { type: "confetti_explosion", text: "hi" } })
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene.metadata["overlay"]).to be_nil
      log = project.generation_logs.where(level: "warn", stage: "direction").last
      expect(log.message).to include("confetti_explosion")
    end

    it "is a no-op, with no warning logged, when direction is absent entirely (pre-Task-4 plan)" do
      provider = stub_provider({})
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene.camera).not_to have_key("movement")
      expect(scene.metadata).not_to have_key("overlay")
      expect(project.generation_logs.where(stage: "direction")).to be_empty
    end
  end

  describe "visual_type validation (Phase 1 Task 4.2 Part B)" do
    def stub_provider(scene_overrides)
      fake = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      base = {
        purpose: "show the press", narration: "The press stamps letters.", caption: "The press",
        duration_seconds: 5, content_type: "cinematic",
        asset_strategy: "image", subject: "a press", environment: "a workshop",
        action: "the press stamps letters", camera: {}, mood: "inventive",
        visual_prompt: "a press", negative_prompt: "", animation: "ken_burns",
        background_music_level: 0.15
      }.merge(scene_overrides)
      json = { scenes: [ base ] }.to_json
      allow(fake).to receive(:chat).and_return(
        Providers::LLM::Result.new(
          text: json, model: "fake-1", provider: "fake", stop_reason: "end_turn",
          usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil
        )
      )
      fake
    end

    it "accepts every PLANNABLE_VISUAL_TYPES value with no warning (chart is guarded to text; see the chart guard spec)" do
      (Scene::PLANNABLE_VISUAL_TYPES - [ "chart" ]).each do |vt|
        project.scenes.destroy_all
        provider = stub_provider(visual_type: vt)
        described_class.new(project: project, provider: provider).call

        expect(project.reload.scenes.first.visual_type).to eq(vt)
      end
      expect(project.generation_logs.where(stage: "direction")).to be_empty
    end

    it "falls back to image and logs a warning for generated_video (not plannable)" do
      provider = stub_provider(visual_type: "generated_video")
      described_class.new(project: project, provider: provider).call

      scene = project.reload.scenes.first
      expect(scene.visual_type).to eq("image")
      log = project.generation_logs.where(level: "warn", stage: "direction").last
      expect(log.message).to include("generated_video").and include("scene_01")
    end

    %w[map split_screen animated_diagram screen_recording].each do |bad|
      it "falls back to image and logs a warning for #{bad}" do
        provider = stub_provider(visual_type: bad)
        described_class.new(project: project, provider: provider).call

        expect(project.reload.scenes.first.visual_type).to eq("image")
        expect(project.generation_logs.where(level: "warn", stage: "direction").last.message).to include(bad)
      end
    end

    it "defaults to image with no warning when visual_type is blank" do
      provider = stub_provider(visual_type: "")
      described_class.new(project: project, provider: provider).call

      expect(project.reload.scenes.first.visual_type).to eq("image")
      expect(project.generation_logs.where(stage: "direction")).to be_empty
    end
  end
end

RSpec.describe Ai::ScenePlannerService, "chart guard (Task 6 A3)" do
  let(:project) { create(:project) }

  it "routes a chart beat to text instead of the image model and logs it" do
    service = described_class.new(project: project)
    visual_type, strategy = service.send(:guard_chart, "chart", "image", "scene_05")

    expect(visual_type).to eq("text_animation")
    expect(strategy).to eq("text")
    expect(project.generation_logs.where(level: "warn").pluck(:message).join).to match(/chart.*routed to text/)
  end

  it "leaves a non-chart image beat alone" do
    service = described_class.new(project: project)
    expect(service.send(:guard_chart, "image", "image", "scene_01")).to eq([ "image", "image" ])
  end
end
