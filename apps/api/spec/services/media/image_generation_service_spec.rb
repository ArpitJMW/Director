require "rails_helper"

RSpec.describe Media::ImageGenerationService do
  let(:project) { project_with_storyboard }
  let(:image_scene) { project.scenes.find { |s| s.visual_type == "image" } }

  it "generates, stores and selects an image for an image scene" do
    asset = described_class.new(scene: image_scene).call

    expect(asset.asset_type).to eq("image")
    expect(asset.source_type).to eq("ai_generated")
    expect(asset.ai_generated).to be(true)
    expect(asset.width).to eq(1280)
    expect(Storage.service.exists?(key: asset.storage_key)).to be(true)

    image_scene.reload
    expect(image_scene.selected_asset).to eq(asset)
    expect(image_scene.status).to eq("ready")
  end

  it "records an image ai_generation with the provider cost" do
    described_class.new(scene: image_scene).call
    gen = project.ai_generations.where(kind: "image").last
    expect(gen.provider_kind).to eq("image")
    expect(gen.status).to eq("succeeded")
  end

  it "skips scenes whose asset_strategy is not image" do
    text_scene = project.scenes.find { |s| s.asset_strategy == "text" }
    expect(described_class.new(scene: text_scene).call).to be_nil
    expect(text_scene.reload.status).to eq("pending")
  end

  it "generates for a scene labeled a non-image visual_type as long as asset_strategy is image " \
     "(Task 2.3 — the 'chart' silent-skip bug: asset_strategy gates generation, not visual_type)" do
    chart_as_image = create(:scene, project: project, visual_type: "chart", asset_strategy: "image",
      visual_prompt: "a bar chart comparing compounding frequencies")

    asset = described_class.new(scene: chart_as_image).call

    expect(asset).to be_present
    expect(chart_as_image.reload.selected_asset).to eq(asset)
    expect(chart_as_image.status).to eq("ready")
  end

  it "marks the scene failed and re-raises on provider error" do
    boom = instance_double(Providers::Image::FakeImageAdapter, name: "fake", default_model: "x")
    allow(boom).to receive(:generate).and_raise(Providers::Image::Base::Error, "no image")

    expect { described_class.new(scene: image_scene, provider: boom).call }
      .to raise_error(Providers::Image::Base::Error)
    expect(image_scene.reload.status).to eq("failed")
  end
end
