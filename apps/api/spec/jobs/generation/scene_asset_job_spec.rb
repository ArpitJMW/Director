require "rails_helper"

RSpec.describe Generation::SceneAssetJob do
  let(:project) { project_with_storyboard }
  let(:scene) { project.scenes.find { |s| s.visual_type == "image" } }

  it "regenerates the image and replaces the previous asset" do
    first = Media::ImageGenerationService.new(scene: scene).call
    gen_job = create(:generation_job, project: project, stage: "assets", queue: "media", scene: scene)
    gen_job.enqueue!

    described_class.new.perform(gen_job.id)

    scene.reload
    expect(scene.selected_asset).to be_present
    expect(scene.selected_asset).not_to eq(first)
    expect(Asset.exists?(first.id)).to be(false)
    expect(Storage.service.exists?(key: first.storage_key)).to be(false)
  end
end
