require "rails_helper"

RSpec.describe Media::VoiceGenerationService do
  let(:project) { project_with_storyboard }
  let(:scene) { project.scenes.first }

  it "creates a voice generation with audio, alignment and captions" do
    vg = described_class.new(scene: scene).call

    expect(vg.status).to eq("succeeded")
    expect(vg.audio_asset.asset_type).to eq("audio")
    expect(vg.duration_seconds).to be > 0
    expect(vg.captions).to be_present
    expect(vg.captions.first).to include("text", "start", "end")
    expect(Storage.service.exists?(key: vg.audio_asset.storage_key)).to be(true)
    expect(scene.reload.current_voice_generation).to eq(vg)
  end

  it "records a voice ai_generation" do
    described_class.new(scene: scene).call
    gen = project.ai_generations.where(kind: "voice").last
    expect(gen.provider_kind).to eq("voice")
    expect(gen.status).to eq("succeeded")
  end

  it "supersedes the previous narration for the scene" do
    first = described_class.new(scene: scene).call
    second = described_class.new(scene: scene).call

    expect(scene.reload.voice_generations.to_a).to eq([ second ])
    expect(VoiceGeneration.exists?(first.id)).to be(false)
    expect(Asset.exists?(first.audio_asset_id)).to be(false)
  end

  it "skips a scene with no narration" do
    scene.update!(narration: "")
    expect(described_class.new(scene: scene).call).to be_nil
  end

  describe "duration reconciliation (Task 2.6)" do
    it "reconciles the scene's duration to the measured audio length plus tail padding" do
      vg = described_class.new(scene: scene).call

      expected = [ vg.duration_seconds.to_f + Media::SceneDurationService::TAIL_PADDING,
                   Media::SceneDurationService::MIN_DURATION ].max
      expect(scene.reload.duration_seconds.to_f).to be_within(0.01).of(expected)
    end

    it "rescales the scene's shots proportionally when it has any" do
      # A single shot spanning the whole (old) scene duration must still span
      # the whole (new) scene duration after reconciliation.
      shot = create(:shot, scene: scene, duration_seconds: scene.duration_seconds)

      vg = described_class.new(scene: scene).call

      expect(shot.reload.duration_seconds.to_f).to be_within(0.01).of(scene.reload.duration_seconds.to_f)
      expect(vg).to be_present
    end

    it "leaves a non-narrated scene's duration untouched" do
      original_duration = scene.duration_seconds
      scene.update!(narration: "")

      described_class.new(scene: scene).call

      expect(scene.reload.duration_seconds).to eq(original_duration)
    end
  end
end
