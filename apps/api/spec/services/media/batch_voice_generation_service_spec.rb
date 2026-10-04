require "rails_helper"

RSpec.describe Media::BatchVoiceGenerationService do
  let(:project) { project_with_storyboard }
  let(:batch_provider) { Providers::Voice::FakeVoiceAdapter.new(supports_batch: true) }

  describe "#generatable?" do
    it "is false when the provider doesn't support batching" do
      service = described_class.new(project: project, provider: Providers::Voice::FakeVoiceAdapter.new)
      expect(service.generatable?).to be(false)
    end

    it "is true for a batch-capable provider with narrated scenes" do
      service = described_class.new(project: project, provider: batch_provider)
      expect(service.generatable?).to be(true)
    end
  end

  describe "#call" do
    it "creates the same per-scene Asset + VoiceGeneration shape the per-scene path produces" do
      service = described_class.new(project: project, provider: batch_provider)
      voice_generations = service.call

      narrated = project.scenes.select { |s| s.narration.present? }
      expect(voice_generations.size).to eq(narrated.size)

      narrated.each do |scene|
        vg = scene.reload.current_voice_generation
        expect(vg).to be_present
        expect(vg.status).to eq("succeeded")
        expect(vg.audio_asset).to be_present
        expect(vg.audio_asset.asset_type).to eq("audio")
        expect(vg.captions).to be_present
      end
    end

    it "records ONE AiGeneration that every resulting VoiceGeneration links to" do
      service = described_class.new(project: project, provider: batch_provider)
      voice_generations = service.call

      gens = AiGeneration.where(project_id: project.id, kind: "voice", provider_kind: "voice")
      expect(gens.count).to eq(1)
      expect(gens.first.request["mode"]).to eq("batch")
      expect(voice_generations.map(&:ai_generation_id).uniq).to eq([ gens.first.id ])
    end

    it "only produces the scenes explicitly passed in, when given an explicit scene list" do
      narrated = project.scenes.select { |s| s.narration.present? }
      subset = [ narrated.first ]
      service = described_class.new(project: project, provider: batch_provider, scenes: subset)

      voice_generations = service.call

      expect(voice_generations.size).to eq(1)
      expect(voice_generations.first.scene_id).to eq(subset.first.id)
    end

    it "skips (does not raise for) a scene whose chunk failed, keeping the others" do
      narrated = project.scenes.select { |s| s.narration.present? }
      failing_provider = instance_double(Providers::Voice::FakeVoiceAdapter,
        name: "fake", default_model: "fake-voice-1", default_voice_id: "fake-voice", supports_batch?: true)
      allow(failing_provider).to receive(:synthesize_batch) do |texts:, voice_id: nil, model: nil|
        real = batch_provider.synthesize_batch(texts: texts, voice_id: voice_id, model: model)
        real[0] = nil # simulate the first scene's chunk failing after retries
        real
      end

      service = described_class.new(project: project, provider: failing_provider, scenes: narrated)
      voice_generations = service.call

      expect(voice_generations.size).to eq(narrated.size - 1)
      expect(narrated.first.reload.current_voice_generation).to be_nil
      expect(project.generation_logs.where(level: "warn", stage: "voice")).to be_present
    end

    it "reconciles each scene's duration to its measured audio length (Task 2.6)" do
      service = described_class.new(project: project, provider: batch_provider)
      voice_generations = service.call

      voice_generations.each do |vg|
        scene = vg.scene.reload
        expected = [ vg.duration_seconds.to_f + Media::SceneDurationService::TAIL_PADDING,
                     Media::SceneDurationService::MIN_DURATION ].max
        expect(scene.duration_seconds.to_f).to be_within(0.01).of(expected)
      end
    end

    it "supersedes a scene's earlier voice generation" do
      described_class.new(project: project, provider: batch_provider).call
      scene = project.scenes.find { |s| s.narration.present? }
      first_vg = scene.reload.current_voice_generation

      described_class.new(project: project, provider: batch_provider).call

      expect(scene.reload.current_voice_generation).not_to eq(first_vg)
      expect(VoiceGeneration.exists?(first_vg.id)).to be(false)
    end
  end
end
