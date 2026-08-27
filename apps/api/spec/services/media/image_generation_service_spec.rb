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

  it "skips scenes whose visual_type is not an image type" do
    text_scene = project.scenes.find { |s| s.visual_type == "text_animation" }
    expect(described_class.new(scene: text_scene).call).to be_nil
    expect(text_scene.reload.status).to eq("pending")
  end

  it "marks the scene failed and re-raises on provider error" do
    boom = instance_double(Providers::Image::FakeImageAdapter, name: "fake", default_model: "x")
    allow(boom).to receive(:generate).and_raise(Providers::Image::Base::Error, "no image")

    expect { described_class.new(scene: image_scene, provider: boom).call }
      .to raise_error(Providers::Image::Base::Error)
    expect(image_scene.reload.status).to eq("failed")
  end
end
