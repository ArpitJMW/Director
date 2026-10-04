require "rails_helper"

RSpec.describe VideoRender do
  let(:project) { create(:project) }

  it "assigns version 1 to a project's first render" do
    render = project.video_renders.create!(width: 1920, height: 1080, fps: 30)
    expect(render.version).to eq(1)
  end

  # Task 4.1 real-run regression: the `version` column's DB-level default of
  # 1 made every new record already truthy before #assign_version ran, so
  # `self.version ||= ...` never actually computed anything past the
  # default — invisible until a project's SECOND render collided with the
  # first on the unique (project_id, version) index.
  it "assigns an incrementing version to a second render on the same project" do
    first = project.video_renders.create!(width: 1920, height: 1080, fps: 30)
    second = project.video_renders.create!(width: 1920, height: 1080, fps: 30)

    expect(first.version).to eq(1)
    expect(second.version).to eq(2)
  end

  it "keeps incrementing across a third render" do
    2.times { project.video_renders.create!(width: 1920, height: 1080, fps: 30) }
    third = project.video_renders.create!(width: 1920, height: 1080, fps: 30)

    expect(third.version).to eq(3)
  end
end
