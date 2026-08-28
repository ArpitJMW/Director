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

  describe "POST /api/v1/projects/:id/storyboard/generate" do
    it "409s when the project has no script yet" do
      post "/api/v1/projects/#{project.public_id}/storyboard/generate", headers: headers
      expect(response).to have_http_status(:conflict)
      expect(json["message"]).to match(/script first/i)
    end

    it "enqueues a storyboard job once a script exists", :inline_jobs do
      Ai::ScriptService.new(project: project).call

      post "/api/v1/projects/#{project.public_id}/storyboard/generate", headers: headers
      expect(response).to have_http_status(:accepted)
      expect(project.reload.scenes.count).to be >= 2
      expect(project.status).to eq("storyboarding")
    end
  end

  describe "POST /api/v1/projects/:id/assets/generate" do
    it "409s without a storyboard" do
      post "/api/v1/projects/#{project.public_id}/assets/generate", headers: headers
      expect(response).to have_http_status(:conflict)
    end

    it "generates images for the storyboard scenes", :inline_jobs do
      Ai::ScriptService.new(project: project).call
      Ai::ScenePlannerService.new(project: project).call

      post "/api/v1/projects/#{project.public_id}/assets/generate", headers: headers
      expect(response).to have_http_status(:accepted)

      image_scenes = project.reload.scenes.select { |s| s.visual_type == "image" }
      expect(image_scenes.map(&:selected_asset)).to all(be_present)
      expect(project.status).to eq("generating_assets")
    end
  end

  describe "POST /api/v1/scenes/:id/assets/regenerate" do
    it "enqueues a single-scene regeneration", :inline_jobs do
      Ai::ScriptService.new(project: project).call
      Ai::ScenePlannerService.new(project: project).call
      scene = project.reload.scenes.find { |s| s.visual_type == "image" }

      post "/api/v1/scenes/#{scene.public_id}/assets/regenerate", headers: headers
      expect(response).to have_http_status(:accepted)
      expect(scene.reload.selected_asset).to be_present
    end

    it "guards by project ownership" do
      scene = create(:scene, project: create(:project))
      post "/api/v1/scenes/#{scene.public_id}/assets/regenerate", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/projects/:id/voice/generate" do
    it "409s without a storyboard" do
      post "/api/v1/projects/#{project.public_id}/voice/generate", headers: headers
      expect(response).to have_http_status(:conflict)
    end

    it "narrates the scenes", :inline_jobs do
      Ai::ScriptService.new(project: project).call
      Ai::ScenePlannerService.new(project: project).call

      post "/api/v1/projects/#{project.public_id}/voice/generate", headers: headers
      expect(response).to have_http_status(:accepted)

      scenes = project.reload.scenes
      expect(scenes.map { |s| s.current_voice_generation }).to all(be_present)
      expect(project.status).to eq("generating_voice")

      get "/api/v1/projects/#{project.public_id}/scenes", headers: headers
      expect(json["scenes"].first["captions"]).to be_present
      expect(json["scenes"].first.dig("narration_audio", "url")).to be_present
    end
  end

  describe "POST /api/v1/projects/:id/render" do
    it "409s without a storyboard" do
      post "/api/v1/projects/#{project.public_id}/render", headers: headers
      expect(response).to have_http_status(:conflict)
    end

    it "enqueues a render job once a storyboard exists" do
      Ai::ScriptService.new(project: project).call
      Ai::ScenePlannerService.new(project: project).call

      expect {
        post "/api/v1/projects/#{project.public_id}/render", headers: headers
      }.to change(Generation::RenderJob.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      expect(project.reload.status).to eq("rendering")
    end
  end

  describe "preflight" do
    it "generates a report and lets the user acknowledge it", :inline_jobs do
      Ai::ScriptService.new(project: project).call
      Ai::ScenePlannerService.new(project: project).call

      post "/api/v1/projects/#{project.public_id}/preflight/generate", headers: headers
      expect(response).to have_http_status(:accepted)

      get "/api/v1/projects/#{project.public_id}/preflight", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json.dig("preflight", "checks")).to include("originality", "advertiser_suitability")
      expect(json.dig("preflight", "disclaimer")).to match(/not.*guarantee/i)

      post "/api/v1/projects/#{project.public_id}/preflight/acknowledge", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json.dig("preflight", "acknowledged_at")).to be_present
    end

    it "409s before a storyboard exists" do
      post "/api/v1/projects/#{project.public_id}/preflight/generate", headers: headers
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "auto pipeline" do
    it "POST /pipeline/start kicks off the chain", :inline_jobs do
      post "/api/v1/projects/#{project.public_id}/pipeline/start", headers: headers
      expect(response).to have_http_status(:accepted)

      project.reload
      expect(project.pipeline_mode).to eq("auto")
      expect(project.pipeline_checkpoint).to eq("storyboard")
      expect(project.scenes.count).to be >= 2
    end

    it "POST /pipeline/continue resumes from the checkpoint", :inline_jobs do
      post "/api/v1/projects/#{project.public_id}/pipeline/start", headers: headers
      post "/api/v1/projects/#{project.public_id}/pipeline/continue", headers: headers

      expect(response).to have_http_status(:accepted)
      expect(project.reload.pipeline_checkpoint).to eq("review")
    end

    it "POST /pipeline/continue 409s when not paused" do
      post "/api/v1/projects/#{project.public_id}/pipeline/continue", headers: headers
      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to eq("not_paused")
    end
  end

  describe "still-stubbed actions" do
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
