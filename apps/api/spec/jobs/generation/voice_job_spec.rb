require "rails_helper"

RSpec.describe Generation::VoiceJob do
  let(:project) { project_with_storyboard }
  let(:gen_job) { create(:generation_job, project: project, stage: "voice", queue: "media") }

  before { gen_job.enqueue! }

  it "narrates every scene with narration and completes" do
    described_class.new.perform(gen_job.id)

    gen_job.reload
    expect(gen_job).to be_succeeded
    expect(project.reload.scenes).to all(satisfy { |s| s.current_voice_generation.present? })
  end

  it "skips scenes already narrated with the same text on re-run" do
    described_class.new.perform(gen_job.id)
    vg_ids = project.reload.scenes.map { |s| s.current_voice_generation.id }

    gen_job.update_column(:status, "queued")
    described_class.new.perform(gen_job.id)

    expect(project.reload.scenes.map { |s| s.current_voice_generation.id }).to match_array(vg_ids)
  end

  it "keeps the scenes that succeeded when some fail (partial failure)" do
    call_count = 0
    allow_any_instance_of(Media::VoiceGenerationService).to receive(:generatable?).and_return(true)
    allow_any_instance_of(Media::VoiceGenerationService).to receive(:call) do
      call_count += 1
      raise StandardError, "tts rate limit" if call_count == 1

      true
    end

    expect { described_class.new.perform(gen_job.id) }.not_to raise_error
    expect(gen_job.reload).to be_succeeded
    expect(gen_job.result["failures"].size).to eq(1)
    expect(project.generation_logs.errors.where(stage: "voice")).to be_present
  end

  it "raises only when every scene fails" do
    allow_any_instance_of(Media::VoiceGenerationService).to receive(:generatable?).and_return(true)
    allow_any_instance_of(Media::VoiceGenerationService).to receive(:call).and_raise(StandardError, "tts down")

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/all .* failed narration/)
  end
end
