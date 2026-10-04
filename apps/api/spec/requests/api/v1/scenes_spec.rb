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

  describe "PATCH /api/v1/scenes/:id — Director panel (Phase 1 Task 3)" do
    let(:scene) { create(:scene, project: project, status: "ready", asset_strategy: "image") }

    it "saves a valid direction edit (camera, transition, overlay) without flagging regeneration" do
      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { direction: {
          camera_motion: "drift", camera_intensity: "high", transition_in: "crossfade",
          overlay: { type: "lower_third", text: "Gutenberg" }
        } } }

      expect(response).to have_http_status(:ok)
      scene.reload
      expect(scene.camera["movement"]).to eq("drift")
      expect(scene.motion["intensity"]).to eq("high")
      expect(scene.transition).to eq("crossfade")
      expect(scene.metadata["overlay"]).to eq("type" => "lower_third", "text" => "Gutenberg")
      expect(scene.status).to eq("ready") # unchanged — direction-only edit
      expect(json["scene"]["needs_regeneration"]).to be(false)
    end

    it "saves text_style/items on a text scene" do
      text_scene = create(:scene, project: project, status: "ready", asset_strategy: "text", visual_type: "text_animation")
      patch "/api/v1/scenes/#{text_scene.public_id}", headers: headers, as: :json,
        params: { scene: { direction: { text_style: "list_reveal", items: %w[Venice Paris Mainz] } } }

      expect(response).to have_http_status(:ok)
      expect(text_scene.reload.metadata["direction_text"]).to eq("text_style" => "list_reveal", "items" => %w[Venice Paris Mainz])
    end

    %w[camera_motion camera_intensity transition_in text_style].each do |field|
      it "rejects an invalid direction.#{field} with 422 and saves nothing" do
        original_transition = scene.transition
        patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
          params: { scene: { direction: { field.to_sym => "not_a_real_value" } } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["messages"].join).to include("not_a_real_value")
        expect(scene.reload.transition).to eq(original_transition) # nothing partially saved
      end
    end

    it "rejects an invalid overlay.type with 422" do
      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { direction: { overlay: { type: "confetti" } } } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["messages"].join).to include("confetti")
    end

    it "rejects an invalid asset_strategy with 422 (only image/text are executable)" do
      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { asset_strategy: "animation" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(scene.reload.asset_strategy).to eq("image")
    end

    it "changing asset_strategy image -> text destroys shots, sets visual_type, and flags regeneration" do
      shot = create(:shot, scene: scene)

      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { asset_strategy: "text" } }

      expect(response).to have_http_status(:ok)
      scene.reload
      expect(scene.asset_strategy).to eq("text")
      expect(scene.visual_type).to eq("text_animation")
      expect(scene.shots).to be_empty
      expect(Shot.exists?(shot.id)).to be(false)
      expect(scene.status).to eq("pending")
      expect(json["scene"]["needs_regeneration"]).to be(true)
    end

    it "changing asset_strategy text -> image sets visual_type back to image and flags regeneration" do
      text_scene = create(:scene, project: project, status: "ready", asset_strategy: "text", visual_type: "text_animation")

      patch "/api/v1/scenes/#{text_scene.public_id}", headers: headers, as: :json,
        params: { scene: { asset_strategy: "image" } }

      expect(response).to have_http_status(:ok)
      text_scene.reload
      expect(text_scene.asset_strategy).to eq("image")
      expect(text_scene.visual_type).to eq("image")
      expect(text_scene.status).to eq("pending")
    end

    it "edits one shot's direction via the nested shots array" do
      shot = create(:shot, scene: scene, camera_movement: "pan_left")

      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { shots: [ { id: shot.public_id, direction: { camera_motion: "drift", camera_intensity: "low" } } ] } }

      expect(response).to have_http_status(:ok)
      shot.reload
      expect(shot.camera_movement).to eq("drift")
      expect(shot.motion["intensity"]).to eq("low")
      expect(scene.reload.status).to eq("ready") # shot direction edit is also re-render-only
    end

    it "rejects an invalid shot direction value with 422 and saves nothing" do
      shot = create(:shot, scene: scene, camera_movement: "pan_left")

      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { shots: [ { id: shot.public_id, direction: { camera_motion: "spin_360" } } ] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(shot.reload.camera_movement).to eq("pan_left")
    end

    it "skips a shots[] entry whose id no longer exists instead of failing the whole update " \
       "(Task 4.1 real-run bug: shots destroyed/recreated between the panel loading and Save " \
       "used to roll back the scene's own direction changes too)" do
      stale_shot_id = create(:shot, scene: scene).public_id
      Shot.find_by(public_id: stale_shot_id).destroy!

      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: {
          direction: { transition_in: "crossfade" },
          shots: [ { id: stale_shot_id, direction: { camera_motion: "drift" } } ]
        } }

      expect(response).to have_http_status(:ok)
      expect(scene.reload.transition).to eq("crossfade")
    end

    it "reports needs_rerender true after a direction edit made since the last completed render" do
      render = create(:video_render, project: project)
      render.start!
      render.start_upload!
      render.complete!

      patch "/api/v1/scenes/#{scene.public_id}", headers: headers, as: :json,
        params: { scene: { direction: { camera_motion: "drift" } } }

      expect(json["scene"]["needs_rerender"]).to be(true)
    end
  end
end
