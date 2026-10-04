require "rails_helper"

RSpec.describe Media::VisualPacing do
  def unit(id, duration, overlay: nil)
    { id: id, duration: duration, camera_movement: "static", overlay: overlay, asset_id: "ast_1" }
  end

  describe ".subdivide" do
    it "leaves units at or under the limit untouched" do
      units = [ unit("a", 4.5), unit("b", 3.2) ]
      expect(described_class.subdivide(units)).to eq(units)
    end

    it "splits a long single unit into parts no longer than the limit, summing exactly" do
      parts = described_class.subdivide([ unit("scene_01", 10.1) ])

      expect(parts.size).to eq(3)
      expect(parts.map { |p| p[:duration] }).to all(be <= 4.5)
      expect(parts.sum { |p| p[:duration] }.round(2)).to eq(10.1)
    end

    it "keeps every part on the same asset (no new image)" do
      parts = described_class.subdivide([ unit("scene_01", 9.0) ])
      expect(parts.map { |p| p[:asset_id] }.uniq).to eq([ "ast_1" ])
    end

    it "alternates two punch-ins on opposite sides so consecutive parts are visibly different (Task 6 F)" do
      parts = described_class.subdivide([ unit("scene_01", 20.0) ])
      moves = parts.map { |p| p[:camera_movement] }

      expect(moves.size).to be >= 5
      expect(moves.uniq).to contain_exactly("punch_in_left", "punch_in_right")
      expect(moves.each_cons(2).all? { |a, b| a != b }).to be true
    end

    it "gives sub-parts unique ids derived from the unit id" do
      parts = described_class.subdivide([ unit("scene_01", 12.0) ])
      expect(parts.map { |p| p[:id] }).to eq(%w[scene_01_p1 scene_01_p2 scene_01_p3])
    end

    it "keeps an overlay on the first part only" do
      parts = described_class.subdivide([ unit("scene_01", 10.0, overlay: { type: "lower_third", text: "Gutenberg" }) ])
      expect(parts.first[:overlay]).to eq(type: "lower_third", text: "Gutenberg")
      expect(parts.drop(1).map { |p| p[:overlay] }).to all(be_nil)
    end

    it "paces each over-long unit in a mixed list while leaving short ones alone" do
      units = [ unit("shot_1", 3.0), unit("shot_2", 10.1), unit("shot_3", 3.0) ]
      paced = described_class.subdivide(units)

      expect(paced.first).to eq(units.first)
      expect(paced.last).to eq(units.last)
      expect(paced[1..-2].sum { |p| p[:duration] }.round(2)).to eq(10.1)
      expect(paced.sum { |p| p[:duration] }.round(2)).to eq(16.1)
    end
  end

  describe ".split_durations" do
    it "always sums to the total at 2 decimals" do
      [ 4.6, 9.99, 13.37, 22.8 ].each do |total|
        durations = described_class.split_durations(total, 4.5)
        expect(durations.sum.round(2)).to eq(total)
        expect(durations.all? { |d| d <= 4.5 }).to be true
      end
    end
  end
end

RSpec.describe Media::RenderManifestBuilder, "Task 5C pacing" do
  let(:project) { project_with_storyboard(aspect_ratio: "16:9") }
  let(:video_render) { project.video_renders.create!(width: 1920, height: 1080, fps: 30) }

  subject(:manifest) do
    described_class.new(project: project, video_render: video_render, asset_base_url: "http://api.test").call
  end

  def scene_json(key)
    manifest[:scenes].find { |s| s[:id] == key }
  end

  it "subdivides a long scene that has no shots into shots reusing the scene's image" do
    scene = project.scenes.order(:position).first
    scene.shots.destroy_all
    scene.update!(asset_strategy: "image", duration_seconds: 10.1)

    shots = scene_json(scene.key)[:shots]

    expect(shots.size).to eq(3)
    expect(shots.sum { |s| s[:duration] }.round(2)).to eq(10.1)
    expect(shots.map { |s| s[:duration] }).to all(be <= 4.5)
  end

  it "leaves a scene already within the limit exactly as before (no shots key added)" do
    scene = project.scenes.order(:position).first
    scene.shots.destroy_all
    scene.update!(asset_strategy: "image", duration_seconds: 4.0)

    expect(scene_json(scene.key)).not_to have_key(:shots)
  end

  it "never paces a text scene" do
    scene = project.scenes.order(:position).first
    scene.shots.destroy_all
    scene.update!(asset_strategy: "text", duration_seconds: 9.0)

    expect(scene_json(scene.key)).not_to have_key(:shots)
  end

  it "does not call any provider while pacing" do
    expect(Providers).not_to receive(:image)
    expect(Providers).not_to receive(:voice)
    scene = project.scenes.order(:position).first
    scene.update!(asset_strategy: "image", duration_seconds: 12.0)

    manifest
  end
end

RSpec.describe Ai::ShotPlanner, "split decision uses narration length (Task 5C)" do
  let(:project) { create(:project) }

  it "targets a short-planned scene whose narration runs long" do
    narration = Array.new(60) { "word" }.join(" ") # 60 words ≈ 27s of speech
    scene = create(:scene, project: project, asset_strategy: "image", visual_prompt: "a press",
                           duration_seconds: 4.0, narration: narration)

    planner = described_class.new(project: project)
    expect(planner.send(:target_scenes)).to include(scene)
  end

  it "does not target a scene whose narration is genuinely short" do
    scene = create(:scene, project: project, asset_strategy: "image", visual_prompt: "a press",
                           duration_seconds: 9.0, narration: "A short line.")

    planner = described_class.new(project: project)
    expect(planner.send(:target_scenes)).not_to include(scene)
  end
end
