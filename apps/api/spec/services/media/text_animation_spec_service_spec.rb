require "rails_helper"

RSpec.describe Media::TextAnimationSpecService do
  let(:project) { create(:project) }
  let(:scene) do
    create(:scene, project: project, visual_type: "text_animation", asset_strategy: "text",
      narration: "The ancient aqueduct carried fresh water across the entire valley for centuries.",
      caption: "Water across the valley", content_type: "documentary", animation: "text_reveal",
      duration_seconds: 6)
  end

  describe "#generatable?" do
    it "is true when the scene has narration or a caption" do
      expect(described_class.new(scene: scene).generatable?).to be(true)
    end

    it "is false with neither" do
      scene.update!(narration: nil, caption: nil)
      expect(described_class.new(scene: scene).generatable?).to be(false)
    end
  end

  describe "#call" do
    it "builds a spec with lines, keywords, emphasis, style and duration — no asset, no provider call" do
      expect(Providers.image).not_to receive(:generate)

      spec = described_class.new(scene: scene).call
      scene.reload

      expect(spec["lines"]).to be_an(Array).and be_present
      expect(spec["keywords"]).to be_an(Array).and be_present
      expect(spec["emphasis"]).to be_an(Array)
      expect(spec["style"]).to eq("documentary")
      expect(spec["animation_style"]).to eq("text_reveal")
      expect(spec["duration"]).to eq(6.0)
      expect(scene.selected_asset).to be_nil
    end

    it "prefers the caption for on-screen lines over the full narration" do
      spec = described_class.new(scene: scene).call
      expect(spec["lines"].join(" ")).to eq(scene.caption)
    end

    it "only emphasizes words that are actually shown" do
      spec = described_class.new(scene: scene).call
      shown = spec["lines"].join(" ").downcase
      expect(spec["emphasis"]).to all(satisfy { |w| shown.include?(w) })
    end

    it "persists production_method and text_spec on the scene's metadata" do
      described_class.new(scene: scene).call
      scene.reload
      expect(scene.metadata["production_method"]).to eq("text")
      expect(scene.metadata["text_spec"]).to eq(scene.to_scene_json[:text_spec])
      expect(scene.status).to eq("ready")
    end

    it "preserves pre-existing metadata keys (e.g. subject/environment from the planner)" do
      scene.update!(metadata: scene.metadata.merge("subject" => "an aqueduct"))
      described_class.new(scene: scene).call
      expect(scene.reload.metadata["subject"]).to eq("an aqueduct")
    end

    it "returns nil and does nothing when not generatable" do
      scene.update!(narration: nil, caption: nil)
      expect(described_class.new(scene: scene).call).to be_nil
      expect(scene.reload.status).to eq("pending")
    end

    it "marks the unit failed and re-raises on error" do
      allow_any_instance_of(described_class).to receive(:build_spec).and_raise(StandardError, "boom")

      expect { described_class.new(scene: scene).call }.to raise_error("boom")
      expect(scene.reload.status).to eq("failed")
      expect(scene.failure_reason).to eq("boom")
    end
  end

  context "with a shot" do
    let(:shot) { create(:shot, scene: scene, asset_strategy: "text", duration_seconds: 3) }

    it "builds a spec for the shot and marks the scene ready once its only shot is ready" do
      spec = described_class.new(scene: scene, shot: shot).call
      expect(spec["duration"]).to eq(3.0)
      expect(shot.reload.metadata["production_method"]).to eq("text")
      expect(shot.status).to eq("ready")
      expect(scene.reload.status).to eq("ready")
    end
  end

  describe "direction_text (Phase 1 Task 4)" do
    it "merges the planner's text_style/items into the built spec" do
      scene.update!(metadata: scene.metadata.merge(
        "direction_text" => { "text_style" => "list_reveal", "items" => %w[Venice Paris Mainz] }
      ))

      spec = described_class.new(scene: scene).call

      expect(spec["text_style"]).to eq("list_reveal")
      expect(spec["items"]).to eq(%w[Venice Paris Mainz])
    end

    it "merges a big_number's number/unit into the built spec" do
      scene.update!(metadata: scene.metadata.merge(
        "direction_text" => { "text_style" => "big_number", "number" => 42, "unit" => "%" }
      ))

      spec = described_class.new(scene: scene).call

      expect(spec["text_style"]).to eq("big_number")
      expect(spec["number"]).to eq(42)
      expect(spec["unit"]).to eq("%")
    end

    it "defaults to the pre-Task-4 shape when the planner set no direction_text" do
      spec = described_class.new(scene: scene).call

      expect(spec).not_to have_key("text_style")
      expect(spec).not_to have_key("items")
    end

    it "caps items at MAX_ITEMS (Task 4.2 Part C — e.g. 6 list items)" do
      scene.update!(metadata: scene.metadata.merge(
        "direction_text" => { "text_style" => "list_reveal", "items" => %w[Venice Paris Mainz Rome Cairo Lima] }
      ))

      spec = described_class.new(scene: scene).call

      expect(spec["items"].size).to eq(described_class::MAX_ITEMS)
      expect(spec["items"]).to eq(%w[Venice Paris Mainz Rome Cairo])
    end

    it "truncates an over-long item with an ellipsis rather than passing it through whole" do
      long_item = "A" * 80
      scene.update!(metadata: scene.metadata.merge(
        "direction_text" => { "text_style" => "timeline", "items" => [ long_item ] }
      ))

      spec = described_class.new(scene: scene).call

      expect(spec["items"].first.length).to eq(described_class::MAX_ITEM_CHARS)
      expect(spec["items"].first).to end_with("…")
    end

    it "does not truncate an item already within the limit" do
      scene.update!(metadata: scene.metadata.merge(
        "direction_text" => { "text_style" => "list_reveal", "items" => [ "Venice" ] }
      ))

      spec = described_class.new(scene: scene).call

      expect(spec["items"]).to eq([ "Venice" ])
    end

    it "truncates an over-long unit" do
      scene.update!(metadata: scene.metadata.merge(
        "direction_text" => { "text_style" => "big_number", "number" => 42, "unit" => "percentage points of the total" }
      ))

      spec = described_class.new(scene: scene).call

      expect(spec["unit"].length).to be <= described_class::MAX_UNIT_CHARS
      expect(spec["unit"]).to end_with("…")
    end

    it "reads the SHOT's own direction_text, not the scene's, when building for a shot" do
      shot = create(:shot, scene: scene, asset_strategy: "text", duration_seconds: 3,
        metadata: { "direction_text" => { "text_style" => "timeline", "items" => [ "1450: Type" ] } })
      scene.update!(metadata: scene.metadata.merge(
        "direction_text" => { "text_style" => "quote" }
      ))

      spec = described_class.new(scene: scene, shot: shot).call

      expect(spec["text_style"]).to eq("timeline")
    end
  end
end
