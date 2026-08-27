require "rails_helper"

RSpec.describe Project, type: :model do
  it "has a valid factory and a public id" do
    project = create(:project)
    expect(project).to be_valid
    expect(project.public_id).to start_with("proj_")
    expect(project.to_param).to eq(project.public_id)
  end

  it "starts in draft" do
    expect(create(:project)).to be_draft
  end

  describe "lifecycle state machine (spec §18)" do
    let(:project) { create(:project) }

    it "advances through the pipeline stages" do
      project.start_script!
      expect(project).to be_script_generating

      project.start_storyboard!
      project.start_assets!
      project.start_voice!
      project.start_captions!
      project.start_render!
      project.start_quality_check!
      expect(project).to be_quality_check

      project.complete!
      expect(project).to be_completed
      expect(project.completed_at).to be_present
    end

    it "records the stage it failed from and resumes there" do
      project.start_script!
      project.start_storyboard!

      project.mark_failed!
      expect(project).to be_failed
      expect(project.failed_from_status).to eq("storyboarding")

      project.resume!
      expect(project).to be_storyboarding
      expect(project.failed_from_status).to be_nil
    end

    it "rejects invalid transitions" do
      expect { project.complete! }.to raise_error(AASM::InvalidTransition)
    end

    it "cannot assign status directly" do
      expect { project.status = "rendering" }.to raise_error(AASM::NoDirectAssignmentError)
    end

    it "can be cancelled from a working state" do
      project.start_script!
      project.cancel!
      expect(project).to be_cancelled
      expect(project.cancelled_at).to be_present
    end
  end

  it "validates target duration bounds" do
    expect(build(:project, target_duration_seconds: 5)).not_to be_valid
    expect(build(:project, target_duration_seconds: 5000)).not_to be_valid
  end

  it "destroys cleanly with a full media pipeline attached" do
    project = project_with_storyboard
    project.scenes.each do |scene|
      Media::VoiceGenerationService.new(scene: scene).call
      Media::ImageGenerationService.new(scene: scene).call
    end

    expect { Project.find(project.id).destroy! }.to change(Asset, :count).to(0)
    expect(VoiceGeneration.count).to eq(0)
    expect(Scene.count).to eq(0)
  end
end
