require "rails_helper"

RSpec.describe "Api::V1::Health", type: :request do
  it "reports ok with database and redis checks" do
    get "/api/v1/health"

    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("ok")
    expect(json["version"]).to eq(Clipify::VERSION)
    expect(json.dig("checks", "database", "status")).to eq("ok")
    expect(json.dig("checks", "redis", "status")).to eq("ok")
  end
end
