# Cross-Origin Resource Sharing for the Next.js frontend.
#
# Origins come from CORS_ORIGINS (comma-separated). Defaults cover local dev.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "http://localhost:3001,http://127.0.0.1:3001").split(","))

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      # devise-jwt returns the token here; the browser must be allowed to read it.
      expose: %w[Authorization],
      max_age: 600
  end
end
