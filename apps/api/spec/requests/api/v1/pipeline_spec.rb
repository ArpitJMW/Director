require "rails_helper"

RSpec.describe "Api::V1::Pipeline", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_header_for(user) }
  let(:project) { create(:project, user: user) }

  describe "POST /api/v1/projects/:id/script/generate" do
    it "enqueues a script job and returns 202" do
      expect {
        post "/api/v1/projects/#{project.public_id}/script/generate", headers: headers
      }.to change(Generation::ScriptJob.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      expect(json.dig("job", "stage")).to eq("script")
      expect(json.dig("job", "status")).to eq("queued")
      expect(project.reload).to be_script_generating
    end

    it "is idempotent while a job is already active" do
      post "/api/v1/projects/#{project.public_id}/script/generate", headers: headers
      first_job = json.dig("job", "id")

      expect {
        post "/api/v1/projects/#{project.public_id}/script/generate", headers: headers
      }.not_to change(Generation::ScriptJob.jobs, :size)

      expect(response).to have_http_status(:accepted)
      expect(json.dig("job", "id")).to eq(first_job)
    end

    it "409s when the project is in a state that can't start script generation" do
      project.start_script!
      project.start_storyboard!

      post "/api/v1/projects/#{project.public_id}/script/generate", headers: headers
      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to eq("invalid_state")
    end

    it "produces a script when the job runs", :inline_jobs do
      post "/api/v1/projects/#{project.public_id}/script/generate", headers: headers

      expect(project.reload.current_script).to be_present
      expect(project.generation_jobs.last).to be_succeeded
    end

    it "enforces ownership" do
      other = create(:project)
      post "/api/v1/projects/#{other.public_id}/script/generate", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "still-stubbed actions" do
    it "returns 501 for rendering" do
      post "/api/v1/projects/#{project.public_id}/render", headers: headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "guards scene regeneration by ownership" do
      scene = create(:scene, project: create(:project))
      post "/api/v1/scenes/#{scene.public_id}/regenerate", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/projects/:id/jobs" do
    it "lists the project's generation jobs" do
      post "/api/v1/projects/#{project.public_id}/script/generate", headers: headers

      get "/api/v1/projects/#{project.public_id}/jobs", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json["jobs"].first["stage"]).to eq("script")
    end
  end
end
