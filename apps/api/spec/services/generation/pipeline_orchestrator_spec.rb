require "rails_helper"

RSpec.describe Generation::PipelineOrchestrator do
  let(:project) { create(:project, topic: "auto pipeline") }

  describe "auto run", :inline_jobs do
    it "chains script -> storyboard -> assets, then pauses at the storyboard checkpoint" do
      described_class.start(project)
      project.reload

      expect(project.pipeline_mode).to eq("auto")
      expect(project.pipeline_checkpoint).to eq("storyboard")
      expect(project.generation_jobs.pluck(:stage)).to include("script", "storyboard", "assets")
      expect(project.generation_jobs.where(stage: "assets").last).to be_succeeded
      expect(project.scenes.count).to be >= 2
      # voice must NOT have run yet
      expect(project.generation_jobs.where(stage: "voice")).to be_empty
    end

    it "continue() resumes voice -> preflight -> render, then pauses at review" do
      described_class.start(project)
      described_class.continue(project.reload)
      project.reload

      expect(project.pipeline_checkpoint).to eq("review")
      expect(project.generation_jobs.pluck(:stage)).to include("voice", "preflight", "render")
      expect(project.preflight_reports).to be_present
      expect(project.video_renders).to be_present
    end

    it "continue() is a no-op when not at a checkpoint" do
      expect(described_class.continue(project)).to be(false)
    end

    it "continue() at the review checkpoint completes the project" do
      described_class.start(project)
      described_class.continue(project.reload) # -> review
      described_class.continue(project.reload) # -> done

      expect(project.reload).to be_completed
      expect(project.pipeline_checkpoint).to be_nil
    end

    it "stop() cancels active jobs and parks the project" do
      described_class.start(project)
      described_class.continue(project.reload) # -> render, review checkpoint

      described_class.stop(project.reload)
      project.reload

      expect(project).to be_cancelled
      expect(project.pipeline_mode).to eq("manual")
      expect(project.pipeline_checkpoint).to be_nil
    end

    it "restart() discards everything and re-runs from the top" do
      described_class.start(project)
      described_class.continue(project.reload)
      old_scene_ids = project.reload.scenes.pluck(:id)
      old_script_ids = project.scripts.pluck(:id)

      described_class.restart(project.reload)
      project.reload

      expect(project.pipeline_mode).to eq("auto")
      expect(project.scenes.pluck(:id) & old_scene_ids).to be_empty
      expect(project.scripts.pluck(:id) & old_script_ids).to be_empty
      expect(project.video_renders).to be_empty
      expect(project.scenes.count).to be >= 2 # fresh run produced a new storyboard
    end

    it "revise() sends a project back to the storyboard checkpoint" do
      described_class.start(project)
      described_class.continue(project.reload)
      described_class.revise(project.reload)

      expect(project.reload.pipeline_checkpoint).to eq("storyboard")
    end
  end

  describe "start() resumes existing work" do
    it "jumps straight to the storyboard checkpoint when scenes already exist" do
      project = project_with_storyboard
      described_class.start(project)
      expect(project.reload.pipeline_checkpoint).to eq("storyboard")
    end
  end

  describe "manual mode" do
    it "advance() does nothing" do
      project.update!(pipeline_mode: "manual")
      expect { described_class.advance(project, "script") }
        .not_to change { project.generation_jobs.count }
    end
  end

  describe ".enqueue" do
    it "returns the existing active job instead of creating a duplicate" do
      first = described_class.enqueue(project, "script")
      second = described_class.enqueue(project, "script")
      expect(second).to eq(first)
    end
  end
end
