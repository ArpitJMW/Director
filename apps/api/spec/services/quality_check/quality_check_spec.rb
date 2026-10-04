require "rails_helper"
require "chunky_png"

RSpec.describe QualityCheck do
  # Synthetic image: textured, with black bars top and bottom (a letterbox).
  def letterboxed_png
    png = ChunkyPNG::Image.new(1376, 768, ChunkyPNG::Color::BLACK)
    768.times do |y|
      next if y < 115 || y >= 653

      1376.times { |x| png[x, y] = ChunkyPNG::Color.rgb(90 + (x % 60), 90, 120) }
    end
    png.to_blob
  end

  let(:project) { create(:project, aspect_ratio: "16:9", settings: {}) }

  def image_scene(attrs = {})
    create(:scene, { project: project, asset_strategy: "image", visual_type: "image",
                     narration: "Plain narration.", duration_seconds: 4, visual_prompt: "a press" }.merge(attrs))
  end

  def stored_asset(scene: nil, shot: nil, key: "projects/1/scenes/1/ast_test.png")
    asset = create(:asset, project: project, scene: scene, shot: shot, asset_type: "image",
                           storage_key: key, width: 1024, height: 1024, content_type: "image/png")
    (shot || scene).update!(selected_asset: asset)
    asset
  end

  describe QualityCheck::Deterministic do
    before { allow(File).to receive(:binread).and_return(ChunkyPNG::Image.new(64, 64, ChunkyPNG::Color::WHITE).to_blob) }

    it "flags a chart beat that reached the image model" do
      scene = image_scene(visual_type: "chart")
      stored_asset(scene: scene)

      issues = QualityCheck::Deterministic.new(project).call
      expect(issues.map { |i| i[:issue_type] }).to include("chart_routed_to_image")
    end

    it "flags narration whose measured audio is far below its word count" do
      scene = image_scene(narration: "Literacy rates rose dramatically across the continent.")
      create(:voice_generation, project: project, scene: scene, status: "succeeded", duration_seconds: 0.06, text: scene.narration)
      stored_asset(scene: scene)

      issues = QualityCheck::Deterministic.new(project).call
      expect(issues.find { |i| i[:issue_type] == "audio_missing" }[:severity]).to eq("high")
    end

    it "does not flag narration whose measured audio covers its word count" do
      scene = image_scene(narration: "Literacy rates rose dramatically across the continent.")
      create(:voice_generation, project: project, scene: scene, status: "succeeded", duration_seconds: 3.4, text: scene.narration)
      stored_asset(scene: scene)

      expect(QualityCheck::Deterministic.new(project).call.map { |i| i[:issue_type] }).not_to include("audio_missing")
    end

    it "flags an image unit with no selected asset" do
      image_scene

      expect(QualityCheck::Deterministic.new(project).call.map { |i| i[:issue_type] }).to include("missing_asset")
    end

    it "reports a 1:1 stored image as informational only, never as a failure" do
      scene = image_scene
      stored_asset(scene: scene)

      aspect = QualityCheck::Deterministic.new(project).call.find { |i| i[:issue_type] == "aspect_mismatch" }
      expect(aspect[:severity]).to eq("info")
    end

    it "detects black letterbox bars still present in a stored image" do
      scene = image_scene
      stored_asset(scene: scene)
      allow(File).to receive(:binread).and_return(letterboxed_png)

      letterbox = QualityCheck::Deterministic.new(project).call.find { |i| i[:issue_type] == "letterbox" }
      expect(letterbox).to be_present
      expect(letterbox[:severity]).to eq("medium")
    end
  end

  describe QualityCheck::VisionReview do
    let(:scene) { image_scene }
    let(:asset) { stored_asset(scene: scene) }
    before { allow(File).to receive(:binread).and_return("bytes") }

    def reviewer(reply: nil, error: nil)
      Providers::Qa::FakeAdapter.new(reply: reply, error: error)
    end

    def review(reply: nil, error: nil)
      described_class.new(project: project, scene: scene, reviewer: reviewer(reply: reply, error: error)).call(asset: asset)
    end

    it "passes an image the model clears" do
      result = review(reply: '{"pass": true, "issues": []}')
      expect(result.status).to eq("passed")
      expect(result.issues).to be_empty
    end

    it "fails on one high issue" do
      reply = '{"issues": [{"type": "era_mismatch", "severity": "high", "evidence": "smartphone is the focus"}]}'
      result = review(reply: reply)

      expect(result.status).to eq("failed")
      expect(result.issues.first).to include(issue_type: "era_mismatch", severity: "high", source: "vision")
    end

    it "passes a single medium issue (Task 6.1: a unit fails on high, or on two or more medium)" do
      reply = '{"issues": [{"type": "subject_mismatch", "severity": "medium", "evidence": "lever not shown"}]}'
      expect(review(reply: reply).status).to eq("passed")
    end

    it "fails on two medium issues together" do
      reply = '{"issues": [{"type": "anatomy", "severity": "medium", "evidence": "odd finger"},' \
              '{"type": "subject_mismatch", "severity": "medium", "evidence": "no action"}]}'
      expect(review(reply: reply).status).to eq("failed")
    end

    it "keeps a low-severity issue without failing the image" do
      reply = '{"pass": true, "issues": [{"type": "other", "severity": "low", "evidence": "slight blur"}]}'
      expect(review(reply: reply).status).to eq("passed")
    end

    it "accepts fenced JSON" do
      reply = "```json\n{\"pass\": false, \"issues\": [{\"type\": \"fake_chart_or_data\", \"severity\": \"high\", \"evidence\": \"numeric axis\"}]}\n```"
      expect(review(reply: reply).status).to eq("failed")
    end

    it "maps an unknown type to other and an unknown severity to medium" do
      reply = '{"pass": false, "issues": [{"type": "vibes", "severity": "extreme", "evidence": "x"}]}'
      issue = review(reply: reply).issues.first
      expect(issue).to include(issue_type: "other", severity: "medium")
    end

    it "marks the unit unavailable on a malformed reply, never raising" do
      result = review(reply: "I think this is fine!")
      expect(result.status).to eq("unavailable")
      expect(result.error).to match(/did not parse/)
    end

    it "marks the unit unavailable when the reply has no issues array" do
      expect(review(reply: '{"verdict": "ok"}').status).to eq("unavailable")
    end

    it "marks the unit unavailable on an ordinary provider error" do
      expect(review(error: StandardError.new("upstream 500")).status).to eq("unavailable")
    end

    it "re-raises a 429 so the run can stop" do
      expect { review(error: Providers::Qa::GeminiVisionAdapter::RateLimited.new("quota")) }
        .to raise_error(Providers::Qa::GeminiVisionAdapter::RateLimited)
    end
  end

  describe QualityCheck::Repair do
    let(:setting) { { "era" => "Germany, c. 1450", "place" => "a Mainz workshop", "wardrobe" => "wool and linen",
                      "avoid" => [ "smartphone" ] } }
    before { project.update!(settings: { "setting" => setting }) }

    def rewriter(prompt: "a craftsman in a Mainz workshop, wool and linen, candlelight", source: "llm")
      double("rewriter", call: { prompt: prompt, source: source })
    end

    describe "strategy selection" do
      it "converts a chart beat to text and generates no image" do
        scene = image_scene(visual_type: "chart", narration: "Literacy rose by 40% in the decade.")
        stored_asset(scene: scene)
        image = double("image")
        allow(image).to receive(:generate)

        result = described_class.new(project: project, provider: image, rewriter: rewriter).call(
          unit: scene, scene: scene, shot: nil, issues: [ { issue_type: "fake_chart_or_data" } ]
        )

        expect(result[:strategy]).to eq("text_conversion:big_number")
        expect(image).not_to have_received(:generate)
        scene.reload
        expect(scene.asset_strategy).to eq("text")
        expect(scene.visual_type).to eq("text_animation")
        expect(scene.metadata["direction_text"]).to include("number" => 40, "unit" => "%")
        expect(scene.selected_asset).to be_nil
      end

      it "uses a period rewrite for an era mismatch" do
        scene = image_scene
        stored_asset(scene: scene)

        result = described_class.new(project: project, provider: Providers::Image::FakeImageAdapter.new,
                                     rewriter: rewriter).call(
          unit: scene, scene: scene, shot: nil, issues: [ { issue_type: "era_mismatch", evidence: "smartphone" } ]
        )

        expect(result[:strategy]).to eq("prompt_rewrite:period:llm")
        expect(result[:outcome]).to eq("repaired")
      end

      it "uses a composition rewrite for gibberish text" do
        scene = image_scene
        stored_asset(scene: scene)

        result = described_class.new(project: project, provider: Providers::Image::FakeImageAdapter.new,
                                     rewriter: rewriter).call(
          unit: scene, scene: scene, shot: nil, issues: [ { issue_type: "gibberish_text", evidence: "invented lettering" } ]
        )

        expect(result[:strategy]).to eq("prompt_rewrite:composition:llm")
      end
    end

    it "passes the setting-first rewritten brief to the image service" do
      scene = image_scene
      stored_asset(scene: scene)
      captured = nil
      allow(Media::ImageGenerationService).to receive(:new) do |**kwargs|
        captured = kwargs
        double("svc", call: nil)
      end

      described_class.new(project: project, provider: Providers::Image::FakeImageAdapter.new,
                          rewriter: rewriter(prompt: "a scribe at a desk, wool sleeves")).call(
        unit: scene, scene: scene, shot: nil, issues: [ { issue_type: "era_mismatch", evidence: "x" } ]
      )

      expect(captured[:brief_override]).to eq("a scribe at a desk, wool sleeves")
      expect(captured[:setting_first]).to be true
    end

    describe "bounds" do
      it "allows one attempt per unit" do
        scene = image_scene
        QualityCheck::Store.write(scene, status: "failed", issues: [],
                                  repair: { "attempts" => 1, "outcome" => "repaired" })

        result = described_class.new(project: project).call(unit: scene.reload, scene: scene, shot: nil,
                                                             issues: [ { issue_type: "anatomy" } ])
        expect(result[:outcome]).to eq("skipped_unit_limit")
      end

      it "stops at the project limit (default 6 repaired units)" do
        6.times do |i|
          unit = image_scene(key: "scene_#{i + 10}", position: i + 10)
          QualityCheck::Store.write(unit, status: "passed", issues: [], repair: { "attempts" => 1, "outcome" => "repaired" })
        end
        fresh = image_scene(key: "scene_99", position: 99)

        result = described_class.new(project: project).call(unit: fresh, scene: fresh, shot: nil, issues: [ { issue_type: "anatomy" } ])
        expect(result[:outcome]).to eq("skipped_project_limit")
      end

      it "reads the project limit from QA_MAX_REPAIRS" do
        ENV["QA_MAX_REPAIRS"] = "2"
        expect(described_class.max_per_project).to eq(2)
      ensure
        ENV.delete("QA_MAX_REPAIRS")
      end
    end
  end

  describe QualityCheck::PromptRewriter do
    let(:scene) { image_scene(action: "a scribe copies a page") }
    let(:rewriter) { described_class.new(project: project, scene: scene, provider: double("llm", name: "fake", default_model: "fake-1")) }

    it "accepts a positive, period-anchored brief" do
      expect(rewriter.valid?("A scribe in wool sleeves copies a page beside a tallow candle in a Mainz workshop")).to be true
    end

    it "rejects a brief that uses negation" do
      expect(rewriter.valid?("A scribe copies a page, no smartphones in view, in a workshop")).to be false
    end

    it "rejects a brief that reintroduces a trigger word" do
      expect(rewriter.valid?("A modern scribe in a workshop copying a page by candlelight in wool")).to be false
    end

    it "rejects a brief that is too short to be useful" do
      expect(rewriter.valid?("A scribe")).to be false
    end

    it "falls back to a deterministic positive brief when the model reply breaks the contract" do
      llm = double("llm", name: "fake", default_model: "fake-1")
      allow(llm).to receive(:chat).and_return(Providers::LLM::Result.new(
        text: '{"visual_prompt": "a modern man, no hat, with a smartphone"}', model: "fake-1", provider: "fake",
        stop_reason: "stop", usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: nil, raw: nil
      ))

      result = described_class.new(project: project, scene: scene, provider: llm).call(problems: [], mode: "period")
      expect(result[:source]).to eq("fallback")
      expect(rewriter.valid?(result[:prompt])).to be true
    end

    it "re-raises a 429 so the run stops" do
      llm = double("llm", name: "fake", default_model: "fake-1")
      allow(llm).to receive(:chat).and_raise(StandardError.new("HTTP 429: quota"))
      expect { described_class.new(project: project, scene: scene, provider: llm).call(problems: [], mode: "period") }
        .to raise_error(StandardError, /429/)
    end
  end

  describe QualityCheck::Verdict do
    it "fails on any high issue" do
      expect(described_class.failing?([ { severity: "high" } ])).to be true
    end

    it "fails on two medium issues but not one" do
      expect(described_class.failing?([ { severity: "medium" } ])).to be false
      expect(described_class.failing?([ { severity: "medium" }, { severity: "medium" } ])).to be true
    end

    it "never fails on low or info issues" do
      expect(described_class.failing?([ { severity: "low" }, { severity: "info" }, { severity: "low" } ])).to be false
    end
  end

  describe "setting injection (Task 6 Part C)" do
    it "injects the project setting into the positive prompt and its anachronisms into the negative" do
      project.update!(settings: { "setting" => { "era" => "Mainz, c. 1450", "place" => "a workshop",
                                                 "wardrobe" => "wool and linen", "technology" => "hand presses",
                                                 "avoid" => [ "smartphones" ] } })
      scene = image_scene(visual_prompt: "a press in a workshop")

      built = Media::ImagePromptBuilder.new(project: project, scene: scene).call
      expect(built[:prompt]).to include("Setting: Mainz, c. 1450").and include("hand presses")
      expect(built[:negative_prompt]).to include("smartphones")
    end

    it "adds no setting clause when none is set" do
      scene = image_scene(visual_prompt: "a press in a workshop")
      expect(Media::ImagePromptBuilder.new(project: project, scene: scene).call[:prompt]).not_to include("Setting:")
    end
  end

  describe Ai::SettingService do
    it "stores one setting per project and does not call the model again" do
      json = { era: "Mainz, c. 1450", place: "a workshop", wardrobe: "wool", technology: "hand press",
               avoid: [ "smartphones", "modern glasses" ] }.to_json
      fake = double("llm", name: "fake", default_model: "fake-1")
      allow(fake).to receive(:chat).and_return(Providers::LLM::Result.new(
        text: json, model: "fake-1", provider: "fake", stop_reason: "stop",
        usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: nil, raw: nil
      ))

      described_class.new(project: project, provider: fake).call
      described_class.new(project: project.reload, provider: fake).call

      expect(project.reload.settings["setting"]["era"]).to eq("Mainz, c. 1450")
      expect(project.settings["setting"]["avoid"]).to eq([ "smartphones", "modern glasses" ])
      expect(fake).to have_received(:chat).once
    end
  end

  describe QualityCheck::Runner do
    before do
      allow_any_instance_of(Ai::SettingService).to receive(:call).and_return({ "era" => "x" })
    end

    it "stops the run on a 429 and says so, without raising" do
      scene = image_scene
      stored_asset(scene: scene)
      allow(File).to receive(:binread).and_return("bytes")
      limited = Providers::Qa::FakeAdapter.new(error: Providers::Qa::GeminiVisionAdapter::RateLimited.new("quota"))

      summary = described_class.new(project: project, reviewer: limited).call

      expect(summary[:stopped]).to match(/rate_limited/)
    end

    it "marks a clean image passed and reports counts" do
      scene = image_scene(narration: nil)
      stored_asset(scene: scene)
      allow(File).to receive(:binread).and_return(ChunkyPNG::Image.new(64, 64, ChunkyPNG::Color::WHITE).to_blob)

      summary = described_class.new(project: project, reviewer: Providers::Qa::FakeAdapter.new).call

      expect(scene.reload.metadata.dig("qa", "status")).to eq("passed")
      expect(summary[:passed]).to be >= 1
      expect(summary[:stopped]).to be_nil
    end
  end
end

RSpec.describe QualityCheck::Runner, "priority (Task 6.1 Part B)" do
  let(:project) { create(:project, settings: {}) }

  it "repairs high-severity units before medium ones" do
    runner = described_class.new(project: project)
    high = { "issues" => [ { "severity" => "high" } ] }
    medium = { "issues" => [ { "severity" => "medium" } ] }

    expect(runner.send(:severity_rank, high)).to be < runner.send(:severity_rank, medium)
  end
end

RSpec.describe Media::ImagePromptBuilder, "setting-first repair prompts (Task 6.1 Part B)" do
  let(:project) { create(:project, settings: { "setting" => { "era" => "Mainz, c. 1450", "avoid" => [ "smartphone" ] } }) }
  let(:scene) { create(:scene, project: project, visual_prompt: "old brief", action: "a scribe copies") }

  it "places the setting at the very start when setting_first is set" do
    built = described_class.new(project: project, scene: scene, brief_override: "a scribe at a desk", setting_first: true).call
    expect(built[:prompt]).to start_with("Setting: Mainz, c. 1450")
    expect(built[:prompt]).to include("a scribe at a desk")
    expect(built[:prompt]).not_to include("old brief")
  end

  it "keeps the setting avoid list in the negative prompt" do
    built = described_class.new(project: project, scene: scene, brief_override: "x", setting_first: true).call
    expect(built[:negative_prompt]).to include("smartphone")
  end
end
