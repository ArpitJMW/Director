require "rails_helper"
require "chunky_png"

RSpec.describe QualityCheck::BatchReview do
  let(:project) { create(:project, aspect_ratio: "16:9", settings: {}) }
  let(:png) { ChunkyPNG::Image.new(64, 64, ChunkyPNG::Color::WHITE).to_blob }

  before { allow(File).to receive(:binread).and_return(png) }

  def unit_for(key, position: 1, risk: 0)
    scene = create(:scene, project: project, key: "scene_#{position}", position: position,
                           asset_strategy: "image", visual_prompt: "a press", narration: "x y z")
    asset = create(:asset, project: project, scene: scene, asset_type: "image", storage_key: "projects/x/#{key}.png",
                           width: 1024, height: 1024, content_type: "image/png")
    scene.update!(selected_asset: asset)
    QualityCheck::BatchReview::Unit.new(key: key, scene: scene, shot: nil, asset: asset, risk: risk)
  end

  def batch_reply(entries)
    { results: entries }.to_json
  end

  it "reviews several images in one request and maps each reply back to its unit" do
    a = unit_for("scene_1", position: 1)
    b = unit_for("scene_2", position: 2)
    reviewer = Providers::Qa::FakeAdapter.new(batch_reply: batch_reply([
      { id: "scene_1", issues: [] },
      { id: "scene_2", issues: [ { type: "era_mismatch", severity: "high", evidence: "smartphone" } ] }
    ]))

    out = described_class.new(project: project, reviewer: reviewer).call([ a, b ])

    expect(out[:calls]).to eq(1)
    expect(out[:reviews]["scene_1"].status).to eq("passed")
    expect(out[:reviews]["scene_2"].status).to eq("failed")
  end

  it "falls back to a single-image review for an image the batch reply left out" do
    a = unit_for("scene_1", position: 1)
    b = unit_for("scene_2", position: 2)
    reviewer = Providers::Qa::FakeAdapter.new(
      reply: '{"issues": []}',
      batch_reply: batch_reply([ { id: "scene_1", issues: [] } ])
    )

    out = described_class.new(project: project, reviewer: reviewer).call([ a, b ])

    expect(out[:reviews]["scene_2"].status).to eq("passed")
    expect(out[:calls]).to eq(2) # the batch request, then one single fallback
  end

  it "marks every unit qa_skipped_quota once the daily limit is reached, without calling the reviewer" do
    a = unit_for("scene_1", position: 1)
    reviewer = Providers::Qa::FakeAdapter.new(batch_reply: batch_reply([]))
    allow(reviewer).to receive(:review_batch).and_call_original

    out = described_class.new(project: project, reviewer: reviewer, daily_limit: 0).call([ a ])

    expect(out[:reviews]["scene_1"].status).to eq("qa_skipped_quota")
    expect(reviewer).not_to have_received(:review_batch)
  end

  it "counts today's QA requests across projects against the limit" do
    AiGeneration.create!(project: create(:project), kind: "quality_check", provider: "fake", provider_kind: "llm",
                         model: "fake-vision-1", status: "succeeded", request: {}, response: {})
    service = described_class.new(project: project, reviewer: Providers::Qa::FakeAdapter.new, daily_limit: 1)

    expect(service.daily_calls_used).to eq(1)
  end

  it "re-raises a 429 so the run stops" do
    a = unit_for("scene_1", position: 1)
    reviewer = Providers::Qa::FakeAdapter.new(error: Providers::Qa::GeminiVisionAdapter::RateLimited.new("quota"))

    expect { described_class.new(project: project, reviewer: reviewer).call([ a ]) }
      .to raise_error(Providers::Qa::GeminiVisionAdapter::RateLimited)
  end

  it "orders the highest-risk units first" do
    low = unit_for("low", position: 1, risk: 0)
    high = unit_for("high", position: 2, risk: 3)
    service = described_class.new(project: project, reviewer: Providers::Qa::FakeAdapter.new)

    ordered = [ low, high ].sort_by { |u| [ -u.risk, u.scene.position ] }
    expect(ordered.map(&:key)).to eq(%w[high low])
    expect(service).to be_present
  end
end
