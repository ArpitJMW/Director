module ApiHelpers
  def json
    JSON.parse(response.body)
  end

  # Signs in via the real endpoint and returns the Authorization header value.
  def auth_header_for(user, password: "password123")
    post "/api/v1/auth/sign_in", params: { user: { email: user.email, password: password } }, as: :json
    { "Authorization" => response.headers["Authorization"] }
  end
end
