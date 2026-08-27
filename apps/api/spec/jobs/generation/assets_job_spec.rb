require "rails_helper"

RSpec.describe Generation::AssetsJob do
  let(:project) { project_with_storyboard }
  let(:gen_job) { create(:generation_job, project: project, stage: "assets", queue: "media") }

  before { gen_job.enqueue! }

  it "generates images for every image scene and completes" do
    described_class.new.perform(gen_job.id)

    gen_job.reload
    expect(gen_job).to be_succeeded
    image_scenes = project.scenes.select { |s| s.visual_type == "image" }
    expect(image_scenes).to all(have_attributes(status: "ready"))
    expect(image_scenes.map(&:selected_asset)).to all(be_present)
  end

  it "skips scenes that are already ready on a re-run" do
    described_class.new.perform(gen_job.id)
    asset_ids = project.reload.scenes.filter_map(&:selected_asset_id)

    gen_job.update_column(:status, "queued")
    described_class.new.perform(gen_job.id)

    expect(project.reload.scenes.filter_map(&:selected_asset_id)).to match_array(asset_ids)
  end

  it "re-raises when a scene fails so Sidekiq retries" do
    allow(Media::ImageGenerationService).to receive(:new).and_wrap_original do |orig, **kwargs|
      service = orig.call(**kwargs)
      allow(service).to receive(:call).and_raise(StandardError, "provider down")
      allow(service).to receive(:generatable?).and_return(true)
      service
    end

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/failed image generation/)
    expect(project.generation_logs.errors.where(stage: "assets")).to be_present
  end
end
