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

  describe "audio-fits-slot guard (Task 2.6)" do
    it "does not warn when Media::SceneDurationService has already reconciled the scene (the normal case)" do
      manifest

      expect(project.generation_logs.where(level: "warn", stage: "render")).to be_empty
    end

    it "logs a warning if a scene's measured audio somehow still exceeds its slot" do
      scene = project.scenes.first
      # Simulate a scene that skipped reconciliation (e.g. a stale record from
      # before Task 2.6): shrink its slot back below its own voice's measured length.
      scene.update!(duration_seconds: [ scene.current_voice_generation.duration_seconds.to_f / 2.0, 0.1 ].max)

      manifest

      log = project.generation_logs.where(level: "warn", stage: "render", scene_id: scene.id).last
      expect(log).to be_present
      expect(log.message).to include(scene.key).and include("exceeds")
    end
  end
end
