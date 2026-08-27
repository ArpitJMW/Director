require "rails_helper"

RSpec.describe "Api::V1::Templates", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_header_for(user) }

  describe "GET /api/v1/templates" do
    it "returns published templates with their latest version config" do
      published = create(:template)
      published.publish_version!(config: { colors: { text: "#000" } })
      create(:template) # draft, unpublished

      get "/api/v1/templates", headers: headers

      expect(response).to have_http_status(:ok)
      slugs = json["templates"].map { |t| t["slug"] }
      expect(slugs).to include(published.slug)
      expect(slugs).not_to include(Template.where(status: "draft").first.slug)
      expect(json["templates"].first["latest_version"]["config"]).to be_present
    end
  end

  describe "GET /api/v1/templates/:id" do
    it "404-style forbids an unpublished template the user doesn't own" do
      draft = create(:template)
      get "/api/v1/templates/#{draft.public_id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
