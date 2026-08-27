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
end
