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
end
