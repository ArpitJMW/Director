require "rails_helper"

RSpec.describe Media::SceneDurationService do
  describe ".reconcile!" do
    it "sets the scene's duration to the measured audio length plus tail padding" do
      scene = create(:scene, duration_seconds: 8.0)

      described_class.reconcile!(scene: scene, measured_duration: 5.6)

      expect(scene.reload.duration_seconds.to_f).to be_within(0.01).of(5.6 + described_class::TAIL_PADDING)
    end

    it "never goes below MIN_DURATION even for a very short measured duration" do
      scene = create(:scene, duration_seconds: 8.0)

      described_class.reconcile!(scene: scene, measured_duration: 0.3)

      expect(scene.reload.duration_seconds.to_f).to eq(described_class::MIN_DURATION)
    end

    it "rescales the scene's shots proportionally so they still sum to the new duration" do
      scene = create(:scene, duration_seconds: 8.0)
      shot_a = create(:shot, scene: scene, duration_seconds: 3.0)
      shot_b = create(:shot, scene: scene, duration_seconds: 5.0)

      described_class.reconcile!(scene: scene, measured_duration: 11.0)
      ratio = (11.0 + described_class::TAIL_PADDING) / 8.0

      shot_a.reload
      shot_b.reload
      expect(shot_a.duration_seconds.to_f).to be_within(0.01).of(3.0 * ratio)
      expect((shot_a.duration_seconds + shot_b.duration_seconds).to_f).to be_within(0.001).of(scene.reload.duration_seconds.to_f)
    end

    it "leaves a scene with no shots alone besides its own duration" do
      scene = create(:scene, duration_seconds: 8.0)

      expect { described_class.reconcile!(scene: scene, measured_duration: 5.0) }.not_to raise_error
      expect(scene.reload.shots).to be_empty
    end

    it "is a no-op when the measured duration already matches the scene's duration" do
      target = (5.0 + described_class::TAIL_PADDING).round(2)
      scene = create(:scene, duration_seconds: target)
      shot = create(:shot, scene: scene, duration_seconds: target)

      described_class.reconcile!(scene: scene, measured_duration: 5.0)

      expect(shot.reload.duration_seconds.to_f).to eq(target) # untouched, not merely unchanged in value
    end
  end
end
