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

  it "re-raises when a scene fails" do
    call_count = 0
    allow_any_instance_of(Media::VoiceGenerationService).to receive(:call) do
      call_count += 1
      raise StandardError, "tts down" if call_count == 1
    end

    expect { described_class.new.perform(gen_job.id) }.to raise_error(/failed narration/)
  end
end
