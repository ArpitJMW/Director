require "rails_helper"

RSpec.describe Media::RenderManifestBuilder do
  let(:project) do
    p = project_with_storyboard(aspect_ratio: "16:9")
    p.scenes.each do |scene|
      Media::ImageGenerationService.new(scene: scene).call
      Media::VoiceGenerationService.new(scene: scene).call
    end
    p.reload
  end
  let(:video_render) { project.video_renders.create!(width: 1920, height: 1080, fps: 30) }

  subject(:manifest) do
    described_class.new(project: project, video_render: video_render, asset_base_url: "http://api.test").call
  end

  it "resolves the storyboard, audio and assets into an absolute-URL manifest" do
    expect(manifest[:width]).to eq(1920)
    expect(manifest[:height]).to eq(1080)
    expect(manifest[:scenes].size).to eq(project.scenes.count)

    scene = manifest[:scenes].first
    expect(scene[:id]).to eq("scene_01")
    expect(scene[:narration_audio_url]).to start_with("http://api.test/api/v1/files")
    expect(scene[:captions]).to be_present

    expect(manifest[:assets]).to be_present
    expect(manifest[:assets].first[:url]).to start_with("http://api.test/")
    expect(manifest[:music]).to be_nil
  end

  it "picks dimensions from the project aspect ratio" do
    project.update!(aspect_ratio: "9:16")
    expect(manifest[:width]).to eq(1080)
    expect(manifest[:height]).to eq(1920)
  end

  it "includes the template version config" do
    template = create(:template)
    version = template.publish_version!(config: { colors: { text: "#fff" } })
    project.update!(template: template, template_version: version)

    expect(manifest[:template]).to eq("colors" => { "text" => "#fff" })
  end

  it "raises when there are no scenes" do
    project.scenes.destroy_all
    expect { manifest }.to raise_error(described_class::Error, /no scenes/)
  end
end
