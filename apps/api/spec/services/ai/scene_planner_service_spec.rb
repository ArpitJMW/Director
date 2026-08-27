require "rails_helper"

RSpec.describe Ai::ScenePlannerService do
  let(:project) { create(:project, topic: "Deep sea vents", target_duration_seconds: 90) }

  before { Ai::ScriptService.new(project: project).call }

  it "creates ordered scenes following the §19 contract" do
    scenes = described_class.new(project: project).call

    expect(scenes.size).to be >= 2
    expect(project.reload.scenes.pluck(:position)).to eq((1..scenes.size).to_a)
    expect(project.scenes.pluck(:key)).to eq(scenes.each_index.map { |i| format("scene_%02d", i + 1) })

    first = project.scenes.first
    expect(Scene::VISUAL_TYPES).to include(first.visual_type)
    expect(first.to_scene_json.keys).to include(:id, :duration, :visual_type, :animation, :transition)
  end

  it "varies the visual treatment (not one image per scene)" do
    described_class.new(project: project).call
    expect(project.reload.scenes.pluck(:visual_type).uniq.size).to be > 1
  end

  it "replaces existing scenes on regeneration" do
    described_class.new(project: project).call
    original_ids = project.reload.scenes.pluck(:id)

    described_class.new(project: project).call
    expect(project.reload.scenes.pluck(:id) & original_ids).to be_empty
  end

  it "records a scene_plan ai_generation" do
    described_class.new(project: project).call
    expect(project.ai_generations.where(kind: "scene_plan").last.status).to eq("succeeded")
  end

  it "raises when there is no current script" do
    project.scripts.update_all(current: false)
    expect { described_class.new(project: project.reload).call }
      .to raise_error(Ai::ScenePlannerService::Error, /no current script/)
  end
end
