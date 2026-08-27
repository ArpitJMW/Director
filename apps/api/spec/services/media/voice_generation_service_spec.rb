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
end
