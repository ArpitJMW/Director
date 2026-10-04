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

  describe "batch routing (Phase 1 Task 2.4 — provider declares supports_batch?)" do
    before { Providers.voice = Providers::Voice::FakeVoiceAdapter.new(supports_batch: true) }

    it "routes through Media::BatchVoiceGenerationService instead of the per-scene loop" do
      narrated = project.scenes.select { |s| s.narration.present? }

      described_class.new.perform(gen_job.id)

      gen_job.reload
      expect(gen_job).to be_succeeded
      expect(gen_job.result["generated"]).to eq(narrated.size)
      expect(project.reload.scenes).to all(satisfy { |s| s.current_voice_generation.present? })
      # one call for the whole project, not one AiGeneration per scene
      expect(AiGeneration.where(project_id: project.id, kind: "voice").count).to eq(1)
    end

    it "reports exactly the scenes a partial batch failure actually lost" do
      narrated = project.scenes.select { |s| s.narration.present? }
      failing = instance_double(Providers::Voice::FakeVoiceAdapter,
        name: "fake", default_model: "fake-voice-1", default_voice_id: "fake-voice", supports_batch?: true)
      allow(failing).to receive(:synthesize_batch) do |texts:, voice_id: nil, model: nil|
        real = Providers::Voice::FakeVoiceAdapter.new.synthesize_batch(texts: texts, voice_id: voice_id, model: model)
        real[0] = nil
        real
      end
      Providers.voice = failing

      expect { described_class.new.perform(gen_job.id) }.not_to raise_error

      gen_job.reload
      expect(gen_job).to be_succeeded
      expect(gen_job.result["generated"]).to eq(narrated.size - 1)
      expect(gen_job.result["failures"].map { |f| f["scene"] }).to eq([ narrated.first.key ])
      expect(narrated.first.reload.current_voice_generation).to be_nil
    end

    it "raises only when the whole batch produces nothing" do
      failing = instance_double(Providers::Voice::FakeVoiceAdapter,
        name: "fake", default_model: "fake-voice-1", default_voice_id: "fake-voice", supports_batch?: true)
      allow(failing).to receive(:synthesize_batch).and_raise(StandardError, "quota exhausted")
      Providers.voice = failing

      expect { described_class.new.perform(gen_job.id) }.to raise_error(/all .* failed narration/)
    end
  end
end
