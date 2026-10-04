require "rails_helper"

RSpec.describe Media::ProductionDispatcher do
  let(:project) { create(:project) }

  describe "strategy \"image\"" do
    let(:scene) { create(:scene, project: project, asset_strategy: "image") }

    it "routes to Media::ImageGenerationService" do
      service = described_class.for(scene: scene)
      expect(service).to be_a(Media::ImageGenerationService)
    end

    it "calls the image provider when driven" do
      expect(Providers.image).to receive(:generate).and_call_original
      described_class.for(scene: scene).call
    end

    it "does not write a fallback log" do
      described_class.for(scene: scene)
      expect(project.generation_logs.where(level: "warn")).to be_empty
    end
  end

  describe "strategy \"text\"" do
    let(:scene) do
      create(:scene, project: project, asset_strategy: "text", visual_type: "text_animation",
        narration: "The bridge stood for two thousand years.", caption: "Two thousand years")
    end

    it "routes to Media::TextAnimationSpecService" do
      service = described_class.for(scene: scene)
      expect(service).to be_a(Media::TextAnimationSpecService)
    end

    it "does NOT call the image provider" do
      expect(Providers.image).not_to receive(:generate)
      described_class.for(scene: scene).call
    end

    it "stores a text_spec on the scene and no asset" do
      described_class.for(scene: scene).call
      scene.reload
      expect(scene.metadata["production_method"]).to eq("text")
      expect(scene.metadata["text_spec"]).to be_present
      expect(scene.selected_asset).to be_nil
    end
  end

  describe "an unsupported strategy" do
    let(:scene) { create(:scene, project: project, asset_strategy: "chart") }

    it "falls back to image, explicitly" do
      service = described_class.for(scene: scene)
      expect(service).to be_a(Media::ImageGenerationService)
    end

    it "records why in a GenerationLog (never a silent fallback)" do
      described_class.for(scene: scene)
      log = project.generation_logs.where(level: "warn").last
      expect(log).to be_present
      expect(log.message).to include("chart").and include("no executor")
    end
  end

  describe "a shot" do
    let(:scene) { create(:scene, project: project, asset_strategy: "image") }
    let(:shot) { create(:shot, scene: scene, asset_strategy: "text") }

    it "reads the shot's own asset_strategy, not the parent scene's" do
      expect(described_class.for(scene: scene, shot: shot)).to be_a(Media::TextAnimationSpecService)
    end
  end
end
