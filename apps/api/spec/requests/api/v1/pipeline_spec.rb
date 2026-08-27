require "rails_helper"

RSpec.describe "Api::V1::Pipeline", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_header_for(user) }
  let(:project) { create(:project, user: user) }

  it "returns 501 for script generation (Phase 3)" do
    post "/api/v1/projects/#{project.public_id}/script/generate", headers: headers
    expect(response).to have_http_status(:not_implemented)
    expect(json["error"]).to eq("not_implemented")
  end

  it "still enforces ownership before the 501" do
    other = create(:project)
    post "/api/v1/projects/#{other.public_id}/render", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it "guards scene-level regeneration by project ownership" do
    scene = create(:scene, project: create(:project)) # not our project
    post "/api/v1/scenes/#{scene.public_id}/regenerate", headers: headers
    expect(response).to have_http_status(:forbidden)
  end
end
