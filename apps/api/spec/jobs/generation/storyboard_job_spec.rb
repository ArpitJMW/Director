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

  it "re-raises and logs on failure" do
    allow(Ai::ScenePlannerService).to receive(:new).and_raise(Ai::ScenePlannerService::Error, "kaboom")

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/kaboom/)
    expect(project.generation_logs.errors).to be_present
  end
end
