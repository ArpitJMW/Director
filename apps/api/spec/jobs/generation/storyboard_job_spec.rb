require "rails_helper"

RSpec.describe Generation::StoryboardJob do
  let(:project) { create(:project) }
  let(:gen_job) { create(:generation_job, project: project, stage: "storyboard", queue: "storyboard") }

  before do
    Ai::ScriptService.new(project: project).call
    gen_job.enqueue!
  end

  it "plans scenes and completes the job" do
    described_class.new.perform(gen_job.id)

    gen_job.reload
    expect(gen_job).to be_succeeded
    expect(gen_job.result["scene_count"]).to eq(project.reload.scenes.count)
    expect(project.scenes.count).to be >= 2
  end

  it "decides shot splits from narration length, not the planner's pre-TTS duration (Task 5C)" do
    described_class.new.perform(gen_job.id)

    # The fake planner plans a 10s scene but its narration is ~9 words
    # (≈4s of speech), so it must NOT be split.
    planned_long = project.reload.scenes.select { |s| s.duration_seconds.to_f > Ai::ShotPlanner::MIN_SPLIT_SECONDS }
    expect(planned_long).to be_present
    expect(planned_long.flat_map { |s| s.shots.to_a }).to be_empty
    expect(gen_job.reload.result["shot_count"]).to eq(0)
  end

  it "does not fail the stage when a shot plan errors" do
    allow(Ai::ShotPlanner).to receive(:new).and_raise(Ai::ShotPlanner::Error, "shot boom")

    expect { described_class.new.perform(gen_job.id) }.not_to raise_error
    expect(gen_job.reload).to be_succeeded
    expect(project.generation_logs.where(level: "warn")).to be_present
  end

  it "re-raises and logs on failure" do
    allow(Ai::ScenePlannerService).to receive(:new).and_raise(Ai::ScenePlannerService::Error, "kaboom")

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/kaboom/)
    expect(project.generation_logs.errors).to be_present
  end
end
