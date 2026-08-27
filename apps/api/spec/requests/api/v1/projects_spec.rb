require "rails_helper"

RSpec.describe "Api::V1::Projects", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_header_for(user) }

  describe "GET /api/v1/projects" do
    it "returns only the current user's projects, newest first" do
      mine_old = create(:project, user: user, created_at: 2.days.ago)
      mine_new = create(:project, user: user, created_at: 1.hour.ago)
      create(:project) # someone else's

      get "/api/v1/projects", headers: headers

      expect(response).to have_http_status(:ok)
      ids = json["projects"].map { |p| p["id"] }
      expect(ids).to eq([ mine_new.public_id, mine_old.public_id ])
      expect(response.headers["X-Total-Count"]).to eq("2")
    end

    it "requires authentication" do
      get "/api/v1/projects"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/projects" do
    it "creates a project owned by the current user" do
      template = create(:template)

      expect {
        post "/api/v1/projects", headers: headers, as: :json, params: {
          project: {
            title: "Roman Aqueducts", topic: "How Rome moved water",
            target_duration_seconds: 90, format: "youtube_long",
            template_id: template.public_id
          }
        }
      }.to change(user.projects, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.dig("project", "id")).to start_with("proj_")
      expect(json.dig("project", "status")).to eq("draft")
      expect(json.dig("project", "template_id")).to eq(template.public_id)
    end

    it "rejects invalid attributes" do
      post "/api/v1/projects", headers: headers, as: :json,
        params: { project: { title: "x", target_duration_seconds: 3 } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/projects/:id" do
    it "includes scenes and the current script" do
      project = create(:project, user: user)
      create(:script, project: project)
      create(:scene, project: project)

      get "/api/v1/projects/#{project.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json.dig("project", "scenes").size).to eq(1)
      expect(json.dig("project", "current_script")).to be_present
    end

    it "404s for another user's project" do
      other = create(:project)
      get "/api/v1/projects/#{other.public_id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/projects/:id" do
    it "updates permitted fields" do
      project = create(:project, user: user)
      patch "/api/v1/projects/#{project.public_id}", headers: headers, as: :json,
        params: { project: { title: "New title", niche: "history" } }

      expect(response).to have_http_status(:ok)
      expect(project.reload.title).to eq("New title")
      expect(project.niche).to eq("history")
    end
  end

  describe "DELETE /api/v1/projects/:id" do
    it "removes the project" do
      project = create(:project, user: user)
      delete "/api/v1/projects/#{project.public_id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(Project.exists?(project.id)).to be(false)
    end
  end
end
