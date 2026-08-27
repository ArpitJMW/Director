require "rails_helper"

RSpec.describe "Api::V1::Scenes", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_header_for(user) }
  let(:project) { create(:project, user: user) }

  describe "GET /api/v1/projects/:project_id/scenes" do
    it "lists scenes in order with the §19 contract inlined" do
      create(:scene, project: project, position: 2, narration: "second")
      create(:scene, project: project, position: 1, narration: "first")

      get "/api/v1/projects/#{project.public_id}/scenes", headers: headers

      expect(response).to have_http_status(:ok)
      narrations = json["scenes"].map { |s| s["scene"]["narration"] }
      expect(narrations).to eq([ "first", "second" ])
      expect(json["scenes"].first["scene"].keys).to include(
        "id", "duration", "visual_type", "animation", "transition", "background_music_level"
      )
    end

    it "forbids access to another user's project" do
      other = create(:project)
      get "/api/v1/projects/#{other.public_id}/scenes", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/scenes/:id" do
    it "applies creator corrections" do
      scene = create(:scene, project: project)

      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { narration: "Rewritten", visual_type: "map", notes: "use a period map" } }

      expect(response).to have_http_status(:ok)
      scene.reload
      expect(scene.narration).to eq("Rewritten")
      expect(scene.visual_type).to eq("map")
      expect(scene.notes).to eq("use a period map")
    end

    it "rejects an invalid visual_type" do
      scene = create(:scene, project: project)
      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { visual_type: "hologram" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
