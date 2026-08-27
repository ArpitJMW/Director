require "rails_helper"

RSpec.describe Script, type: :model do
  let(:project) { create(:project) }

  it "auto-increments version per project" do
    first = create(:script, project: project)
    second = create(:script, project: project)

    expect(first.version).to eq(1)
    expect(second.version).to eq(2)
  end

  it "keeps only one current script per project" do
    first = create(:script, project: project)
    second = create(:script, project: project)

    expect(second.reload).to be_current
    expect(first.reload).not_to be_current
    expect(project.scripts.current.count).to eq(1)
  end

  it "is reachable as project.current_script" do
    create(:script, project: project)
    latest = create(:script, project: project)
    expect(project.reload.current_script).to eq(latest)
  end
end
