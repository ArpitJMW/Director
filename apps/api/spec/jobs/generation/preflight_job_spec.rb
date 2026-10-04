require "rails_helper"

RSpec.describe Generation::PreflightJob do
  let(:project) { project_with_storyboard }
  let(:gen_job) { create(:generation_job, project: project, stage: "preflight", queue: "policy") }

  before { gen_job.enqueue! }

  it "creates a preflight report and completes" do
    described_class.new.perform(gen_job.id)

    gen_job.reload
    expect(gen_job).to be_succeeded
    report = project.preflight_reports.last
    expect(report).to be_present
    expect(gen_job.result["preflight_report_id"]).to eq(report.public_id)
  end

  # Task 4.3 Part 5: mirrors VoiceJob#pending?'s already-succeeded-and-
  # input-unchanged guard — re-running (e.g. every "continue" from the
  # review checkpoint, including a retry-from-here after an unrelated
  # render failure) used to always fire a fresh real preflight call.
  it "reuses the existing report on a second run when nothing changed" do
    described_class.new.perform(gen_job.id)
    first_report = project.preflight_reports.last

    second_job = create(:generation_job, project: project, stage: "preflight", queue: "policy")
    second_job.enqueue!
    described_class.new.perform(second_job.id)

    second_job.reload
    expect(second_job).to be_succeeded
    expect(project.preflight_reports.count).to eq(1)
    expect(second_job.result["preflight_report_id"]).to eq(first_report.public_id)
    expect(second_job.result["skipped"]).to eq(true)
  end

  it "runs a fresh preflight when a scene changed since the last report" do
    described_class.new.perform(gen_job.id)
    first_report = project.preflight_reports.last

    project.scenes.first.touch

    second_job = create(:generation_job, project: project, stage: "preflight", queue: "policy")
    second_job.enqueue!
    described_class.new.perform(second_job.id)

    second_job.reload
    expect(project.preflight_reports.count).to eq(2)
    expect(second_job.result["preflight_report_id"]).not_to eq(first_report.public_id)
    expect(second_job.result["skipped"]).to be_nil
  end
end
