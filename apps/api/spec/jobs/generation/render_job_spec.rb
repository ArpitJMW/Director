require "rails_helper"

RSpec.describe Generation::RenderJob do
  let(:project) do
    p = project_with_storyboard
    p.scenes.each do |scene|
      Media::ImageGenerationService.new(scene: scene).call
      Media::VoiceGenerationService.new(scene: scene).call
    end
    p.reload
  end
  let(:gen_job) { create(:generation_job, project: project, stage: "render", queue: "render") }

  before do
    gen_job.enqueue!
    fake_mp4 = "\x00\x00\x00\x18ftypmp42".b + ("\x00".b * 512)
    allow_any_instance_of(Video::RenderVideo).to receive(:call).and_return(
      { path: "/tmp/x.mp4", render_seconds: 4.2, bytes: fake_mp4 }
    )
  end

  it "builds a manifest, renders, stores the MP4 and completes the VideoRender" do
    described_class.new.perform(gen_job.id)

    gen_job.reload
    expect(gen_job).to be_succeeded

    render = project.video_renders.last
    expect(render.status).to eq("completed")
    expect(render.manifest["scenes"].size).to eq(project.scenes.count)
    expect(render.output_asset.asset_type).to eq("video")
    expect(render.output_asset.content_type).to eq("video/mp4")
    expect(render.render_seconds).to eq(4.2)
    expect(render.duration_seconds).to be > 0
    expect(Storage.service.exists?(key: render.output_asset.storage_key)).to be(true)
  end

  it "marks the VideoRender failed and re-raises when the renderer errors" do
    allow_any_instance_of(Video::RenderVideo).to receive(:call)
      .and_raise(Video::RenderVideo::Error, "chrome missing")

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/chrome missing/)
    expect(project.video_renders.last.status).to eq("failed")
  end

  describe "render safety for scenes with no audio (Phase 1 Task 2.4)" do
    it "warns clearly but still renders — never blocks — when a narrated scene has no audio" do
      silent_scene = project.scenes.first
      silent_scene.current_voice_generation.audio_asset&.destroy
      silent_scene.current_voice_generation.destroy

      described_class.new.perform(gen_job.id)

      gen_job.reload
      expect(gen_job).to be_succeeded # not blocked

      render = project.video_renders.last
      expect(render.status).to eq("completed")
      expect(render.log).to include(silent_scene.key).and include("no audio")
      expect(project.generation_logs.where(level: "warn", stage: "render")).to be_present
    end

    it "leaves the render log blank when every narrated scene has audio" do
      described_class.new.perform(gen_job.id)

      render = project.video_renders.last
      expect(render.log).to be_blank
      expect(project.generation_logs.where(level: "warn", stage: "render")).to be_empty
    end
  end
end
