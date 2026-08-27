require "rails_helper"

RSpec.describe GenerationJob, type: :model do
  let(:project) { create(:project) }

  it "assigns an idempotency key and public id" do
    job = create(:generation_job, project: project)
    expect(job.public_id).to start_with("job_")
    expect(job.idempotency_key).to be_present
  end

  it "rejects a duplicate idempotency key" do
    create(:generation_job, project: project, idempotency_key: "fixed-key")
    dup = build(:generation_job, project: project, idempotency_key: "fixed-key")
    expect(dup).not_to be_valid
  end

  describe "state machine" do
    let(:job) { create(:generation_job, project: project, max_attempts: 2) }

    it "counts attempts on start and stops retrying past the limit" do
      job.enqueue!
      job.start!
      expect(job.attempts).to eq(1)

      expect(job.retry_later!).to be(true)
      job.start!
      expect(job.attempts).to eq(2)

      expect(job.may_retry_later?).to be(false)
    end

    it "moves to failed and records finished_at" do
      job.enqueue!
      job.start!
      job.mark_failed!
      expect(job).to be_failed
      expect(job.finished_at).to be_present
    end
  end
end
