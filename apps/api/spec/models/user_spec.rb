require "rails_helper"

RSpec.describe User, type: :model do
  it "has a valid factory" do
    expect(build(:user)).to be_valid
  end

  it "requires a name" do
    expect(build(:user, name: "")).not_to be_valid
  end

  it "requires a unique email" do
    create(:user, email: "dup@example.com")
    expect(build(:user, email: "dup@example.com")).not_to be_valid
  end

  it "normalizes email to lowercase and trimmed" do
    user = create(:user, email: "  MixedCase@Example.com  ")
    expect(user.email).to eq("mixedcase@example.com")
  end
end
