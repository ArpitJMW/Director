require "rails_helper"

RSpec.describe AiGeneration do
  let(:project) { create(:project) }

  # AiGeneration.track! previously only ever received a single Result. Phase 1
  # Task 2.4 taught it to also accept an Array (one batch call covering many
  # scenes' voice narration) — these specs cover that addition directly, in
  # isolation from Media::BatchVoiceGenerationService's end-to-end behaviour.
  describe ".track! with an Array result (batch calls)" do
    def fake_result(cost:, provider_request_id:)
      Providers::Voice::Result.new(
        audio_bytes: "", content_type: "audio/wav", alignment: {}, duration_seconds: 1.0,
        model: "m", provider: "fake", provider_request_id: provider_request_id,
        cost_usd: cost, raw: nil
      )
    end

    it "records ONE AiGeneration, summing cost across every element" do
      described_class.track!(
        project: project, kind: "voice", provider: "fake", model: "m", provider_kind: "voice"
      ) { [ fake_result(cost: 0.01, provider_request_id: "a"), fake_result(cost: 0.02, provider_request_id: "b") ] }

      record = described_class.where(project: project, kind: "voice").last
      expect(described_class.where(project: project, kind: "voice").count).to eq(1)
      expect(record.status).to eq("succeeded")
      expect(record.cost_usd).to eq(0.03)
      expect(record.provider_request_id).to eq("a,b")
      expect(record.response["batch_size"]).to eq(2)
    end

    it "tolerates nil entries — uses the first real entry for bookkeeping and ignores nils in cost/id aggregation" do
      described_class.track!(
        project: project, kind: "voice", provider: "fake", model: "m", provider_kind: "voice"
      ) { [ nil, fake_result(cost: 0.05, provider_request_id: "only") ] }

      record = described_class.where(project: project, kind: "voice").last
      expect(record.status).to eq("succeeded")
      expect(record.cost_usd).to eq(0.05)
      expect(record.provider_request_id).to eq("only")
    end

    it "returns the original array (including nils) to the caller unchanged" do
      result = described_class.track!(
        project: project, kind: "voice", provider: "fake", model: "m", provider_kind: "voice"
      ) { [ fake_result(cost: 0.0, provider_request_id: "x"), nil ] }

      expect(result.size).to eq(2)
      expect(result.last).to be_nil
    end
  end

  describe ".track! with a single result (unchanged)" do
    it "still works exactly as before" do
      result = described_class.track!(
        project: project, kind: "voice", provider: "fake", model: "m", provider_kind: "voice"
      ) { fake_result_single }

      record = described_class.where(project: project, kind: "voice").last
      expect(record.status).to eq("succeeded")
      expect(record.provider_request_id).to eq("solo")
      expect(result).not_to be_an(Array)
    end

    def fake_result_single
      Providers::Voice::Result.new(
        audio_bytes: "", content_type: "audio/wav", alignment: {}, duration_seconds: 1.0,
        model: "m", provider: "fake", provider_request_id: "solo", cost_usd: 0.01, raw: nil
      )
    end
  end
end
