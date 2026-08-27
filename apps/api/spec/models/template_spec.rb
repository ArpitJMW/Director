require "rails_helper"

RSpec.describe Template, type: :model do
  it "publishes versions and points latest_version at the newest" do
    template = create(:template)

    v1 = template.publish_version!(config: { colors: { text: "#000" } }, changelog: "first")
    expect(template.reload.status).to eq("published")
    expect(template.latest_version).to eq(v1)

    v2 = template.publish_version!(config: { colors: { text: "#fff" } })
    expect(template.reload.latest_version).to eq(v2)
    expect(v2.version).to eq(2)
    expect(template.versions.count).to eq(2)
  end

  it "validates slug format" do
    expect(build(:template, slug: "Not Valid")).not_to be_valid
    expect(build(:template, slug: "dark-documentary-2")).to be_valid
  end

  it "seeds the five initial templates" do
    load Rails.root.join("db/seeds.rb")
    expect(Template.built_in.published.pluck(:slug)).to include(
      "dark-documentary", "modern-tech", "historical-documentary",
      "cartoon-explainer", "minimal-educational"
    )
  end
end
