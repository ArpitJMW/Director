require "rails_helper"

RSpec.describe "Api::V1::Auth", type: :request do
  describe "POST /api/v1/auth/sign_up" do
    let(:params) do
      { user: { name: "Arpit", email: "new@example.com", password: "password123" } }
    end

    it "creates a user and returns a JWT" do
      expect {
        post "/api/v1/auth/sign_up", params: params, as: :json
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.headers["Authorization"]).to start_with("Bearer ")
      expect(json.dig("user", "email")).to eq("new@example.com")
    end

    it "rejects a duplicate email" do
      create(:user, email: "new@example.com")

      post "/api/v1/auth/sign_up", params: params, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["messages"].join).to match(/email/i)
    end
  end

  describe "POST /api/v1/auth/sign_in" do
    let!(:user) { create(:user, password: "password123") }

    it "returns a JWT for valid credentials" do
      post "/api/v1/auth/sign_in",
        params: { user: { email: user.email, password: "password123" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["Authorization"]).to start_with("Bearer ")
    end

    it "rejects invalid credentials" do
      post "/api/v1/auth/sign_in",
        params: { user: { email: user.email, password: "wrong" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "authenticated access to /api/v1/me" do
    let!(:user) { create(:user) }

    it "requires a token" do
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user with a valid token" do
      get "/api/v1/me", headers: auth_header_for(user)

      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "id")).to eq(user.id)
    end

    it "rejects a token after sign out" do
      headers = auth_header_for(user)

      delete "/api/v1/auth/sign_out", headers: headers
      expect(response).to have_http_status(:ok)

      get "/api/v1/me", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
