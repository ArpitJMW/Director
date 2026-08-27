module Api
  module V1
    # Readiness probe. Unlike /up (liveness), this verifies the app can reach
    # its backing services.
    class HealthController < ApplicationController
      def show
        checks = {
          database: check { ActiveRecord::Base.connection.execute("SELECT 1") },
          redis: check { Sidekiq.redis(&:ping) == "PONG" }
        }

        ok = checks.values.all? { |c| c[:status] == "ok" }
        render json: {
          status: ok ? "ok" : "degraded",
          version: Clipify::VERSION,
          time: Time.current.iso8601,
          checks: checks
        }, status: ok ? :ok : :service_unavailable
      end

      private

      def check
        yield
        { status: "ok" }
      rescue => e
        { status: "error", detail: e.message }
      end
    end
  end
end
