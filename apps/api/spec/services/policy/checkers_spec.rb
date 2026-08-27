require "rails_helper"

RSpec.describe "Policy checkers" do
  let(:project) { project_with_storyboard }

  describe Policy::NarrativeValueChecker do
    it "warns when narration is sparse" do
      project.scenes.update_all(narration: "Too short.", duration_seconds: 20)
      expect(described_class.call(project: project.reload).verdict).to eq("warn")
    end

    it "passes with substantial narration" do
      project.scenes.each { |s| s.update!(narration: "word " * 40, duration_seconds: 10) }
      expect(described_class.call(project: project.reload).verdict).to eq("pass")
    end
  end

  describe Policy::RepetitionChecker do
    it "passes with no prior videos" do
      expect(described_class.call(project: project).verdict).to eq("pass")
    end

    it "warns when the script closely matches a recent completed video" do
      narration = project.current_script.full_narration
      twin = create(:project, user: project.user)
      twin.update_column(:status, "completed")
      create(:script, project: twin, full_narration: narration)

      expect(described_class.call(project: project.reload).verdict).to eq("warn")
    end
  end

  describe Policy::ProvenanceChecker do
    it "warns when an image scene has no asset" do
      expect(described_class.call(project: project).verdict).to eq("warn")
    end

    it "passes once images and audio are generated" do
      project.scenes.each do |scene|
        Media::ImageGenerationService.new(scene: scene).call
        Media::VoiceGenerationService.new(scene: scene).call
      end
      expect(described_class.call(project: project.reload).verdict).to eq("pass")
    end
  end

  describe Policy::ReuseChecker do
    it "warns when narration copies long runs from a source" do
      lifted = project.current_script.full_narration
      create(:source, project: project, raw_excerpt: lifted)
      expect(described_class.call(project: project.reload).verdict).to eq("warn")
    end

    it "passes when there are no sources" do
      expect(described_class.call(project: project).verdict).to eq("pass")
    end
  end

  describe Policy::DisclosureChecker do
    it "returns not_required for stylised AI assets" do
      create(:asset, project: project, ai_generated: true, realistic: false)
      expect(described_class.call(project: project).verdict).to eq("not_required")
    end

    it "returns review for realistic AI assets" do
      create(:asset, project: project, ai_generated: true, realistic: true)
      expect(described_class.call(project: project).verdict).to eq("review")
    end

    it "returns required when a realistic asset depicts a real person" do
      create(:asset, project: project, ai_generated: true, realistic: true, represents_real_person: true)
      expect(described_class.call(project: project).verdict).to eq("required")
    end
  end

  describe Policy::CopyrightChecker do
    it "warns when a licensed asset has no license string" do
      create(:asset, project: project, source_type: "licensed", license: nil)
      expect(described_class.call(project: project).verdict).to eq("warn")
    end
  end

  describe Policy::OriginalityChecker do
    it "passes for a scripted project (fake provider)" do
      expect(described_class.call(project: project).verdict).to eq("pass")
    end

    it "reviews when there is no script" do
      project.scripts.destroy_all
      expect(described_class.call(project: project.reload).verdict).to eq("review")
    end
  end
end

RSpec.describe Policy::PreflightEngine do
  let(:project) do
    p = project_with_storyboard
    p.scenes.each do |scene|
      scene.update!(narration: "word " * 30, duration_seconds: 8)
      Media::ImageGenerationService.new(scene: scene).call
      Media::VoiceGenerationService.new(scene: scene).call
    end
    p.reload
  end

  it "produces a report with all §32 rows" do
    report = described_class.new(project: project).call

    expect(report.checks.keys).to contain_exactly(
      "originality", "narrative_value", "repetition_risk", "asset_provenance",
      "reuse_risk", "copyright_license", "advertiser_suitability"
    )
    expect(report.checks["advertiser_suitability"]).to eq("review")
    expect(report.ai_disclosure).to eq("not_required")
    expect(report.status).to eq("ready")
  end

  it "is review_required when a gating check warns" do
    create(:asset, project: project, source_type: "licensed", license: nil)
    report = described_class.new(project: project).call
    expect(report.status).to eq("review_required")
    expect(report.warnings.map { |w| w["check"] }).to include("copyright_license")
  end
end
