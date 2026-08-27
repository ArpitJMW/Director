require "rails_helper"

RSpec.describe Generation::ScriptJob do
  let(:project) { create(:project) }
  let(:gen_job) { create(:generation_job, project: project, stage: "script", queue: "script") }

  before { gen_job.enqueue! }

  it "runs the script service and completes the job" do
    described_class.new.perform(gen_job.id)

    gen_job.reload
    expect(gen_job).to be_succeeded
    expect(gen_job.attempts).to eq(1)
    expect(gen_job.result["script_id"]).to eq(project.reload.current_script.public_id)
  end

  it "is a no-op if the job already succeeded" do
    gen_job.start!
    gen_job.succeed!

    expect { described_class.new.perform(gen_job.id) }.not_to change(project.scripts, :count)
  end

  it "re-raises on failure so Sidekiq can retry, leaving a log line" do
    allow(Ai::ScriptService).to receive(:new).and_raise(Ai::ScriptService::Error, "boom")

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/boom/)
    expect(project.generation_logs.errors).to be_present
    expect(gen_job.reload.failure_reason).to eq("boom")
  end
end
