require "rails_helper"

RSpec.describe "Api::V1::Assets", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_header_for(user) }
  let(:project) { create(:project, user: user) }
  let(:upload) do
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/sample.png"), "image/png")
  end

  describe "POST /api/v1/projects/:project_id/assets" do
    it "stores a user-provided upload" do
      expect {
        post "/api/v1/projects/#{project.public_id}/assets",
          headers: headers, params: { file: upload, asset_type: "image" }
      }.to change(project.assets, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.dig("asset", "source_type")).to eq("user_provided")
      expect(json.dig("asset", "url")).to start_with("/api/v1/files?")
      expect(json.dig("asset", "width")).to eq(2)
    end

    it "rejects an unsupported content type" do
      bad = Rack::Test::UploadedFile.new(StringIO.new("hi"), "application/x-msdownload", original_filename: "x.exe")
      post "/api/v1/projects/#{project.public_id}/assets", headers: headers, params: { file: bad }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "forbids uploading to another user's project" do
      other = create(:project)
      post "/api/v1/projects/#{other.public_id}/assets", headers: headers, params: { file: upload }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/assets" do
    it "lists the user's assets scoped by project" do
      Asset.store!(project: project, asset_type: "image",
        io: File.open(Rails.root.join("spec/fixtures/files/sample.png")),
        content_type: "image/png", source_type: "user_provided")

      get "/api/v1/assets", headers: headers, params: { project_id: project.public_id }
      expect(response).to have_http_status(:ok)
      expect(json["assets"].size).to eq(1)
    end
  end

  describe "GET /api/v1/files (disk delivery)" do
    it "serves the object for a valid signed url and 403s a tampered one" do
      asset = Asset.store!(project: project, asset_type: "image",
        io: File.open(Rails.root.join("spec/fixtures/files/sample.png")),
        content_type: "image/png", source_type: "user_provided")

      get asset.signed_url
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("image/png")

      get asset.signed_url.sub(/token=\w+/, "token=deadbeef")
      expect(response).to have_http_status(:forbidden)
    end
  end
end
