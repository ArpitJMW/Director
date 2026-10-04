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

  it "re-raises only when every unit — across every production method — fails" do
    # project_with_storyboard's fixture also contains a text_animation scene
    # (Phase 1 Task 2), so "everything fails" has to fail both paths, not just
    # the image one, for the stage to actually be a total wipeout.
    allow(Media::ImageGenerationService).to receive(:new).and_wrap_original do |orig, **kwargs|
      service = orig.call(**kwargs)
      allow(service).to receive(:call).and_raise(StandardError, "provider down")
      allow(service).to receive(:generatable?).and_return(true)
      service
    end
    allow(Media::TextAnimationSpecService).to receive(:new).and_wrap_original do |orig, **kwargs|
      service = orig.call(**kwargs)
      allow(service).to receive(:call).and_raise(StandardError, "spec build failed")
      allow(service).to receive(:generatable?).and_return(true)
      service
    end

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/failed generation/)
    expect(project.generation_logs.errors.where(stage: "assets")).to be_present
  end

  it "produces a text scene AND generates an image scene in the same run (methods coexist)" do
    described_class.new.perform(gen_job.id)
    project.reload

    text_scene = project.scenes.find { |s| s.asset_strategy == "text" }
    image_scene = project.scenes.find { |s| s.visual_type == "image" }

    expect(text_scene.metadata["production_method"]).to eq("text")
    expect(text_scene.metadata["text_spec"]).to be_present
    expect(text_scene.selected_asset).to be_nil
    expect(text_scene.status).to eq("ready")

    expect(image_scene.selected_asset).to be_present
    expect(image_scene.metadata["production_method"]).to be_nil # image path is unchanged, doesn't stamp this
  end

  it "generates a chart-labeled scene whose asset_strategy is image (Task 2.3 — the silent-skip bug)" do
    project.scenes.create!(
      position: project.scenes.maximum(:position).to_i + 1,
      key: "scene_chart", visual_type: "chart", asset_strategy: "image",
      visual_prompt: "a bar chart comparing three options", duration_seconds: 5
    )

    described_class.new.perform(gen_job.id)

    chart_scene = project.reload.scenes.find_by(visual_type: "chart")
    expect(chart_scene.status).to eq("ready")
    expect(chart_scene.selected_asset).to be_present
  end

  it "never leaves a unit silently pending — marks it failed with a reason instead" do
    project.scenes.create!(
      position: project.scenes.maximum(:position).to_i + 1,
      key: "scene_blank", visual_type: "image", asset_strategy: "image",
      visual_prompt: nil, duration_seconds: 5
    )

    described_class.new.perform(gen_job.id) # does not raise — other scenes still succeed

    blank_scene = project.reload.scenes.find_by(key: "scene_blank")
    expect(blank_scene.status).to eq("failed")
    expect(blank_scene.failure_reason).to be_present
    expect(project.generation_logs.where(level: "warn", stage: "assets")).to be_present
  end

  it "a partial failure on one method does not block the other from succeeding" do
    allow(Media::ImageGenerationService).to receive(:new).and_wrap_original do |orig, **kwargs|
      service = orig.call(**kwargs)
      allow(service).to receive(:call).and_raise(StandardError, "provider down")
      allow(service).to receive(:generatable?).and_return(true)
      service
    end

    described_class.new.perform(gen_job.id) # does not raise — the text scene succeeded
    text_scene = project.reload.scenes.find { |s| s.asset_strategy == "text" }
    expect(text_scene.status).to eq("ready")
  end
end
