module Api
  module V1
    # Authenticated base: JWT auth + Pundit available. Does NOT force
    # authorization checks — see ResourceController for that.
    class BaseController < ApplicationController
      include Pundit::Authorization
      include Pagy::Backend

      before_action :authenticate_user!

      rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
      rescue_from Pundit::NotDefinedError, with: :render_forbidden

      private

      def render_forbidden(_error = nil)
        render json: { error: "forbidden" }, status: :forbidden
      end

      # Returns the page of records and sets pagination response headers.
      def paginate(scope)
        pagy, records = pagy(scope, limit: params[:per_page])
        response.set_header("X-Total-Count", pagy.count.to_s)
        response.set_header("X-Page", pagy.page.to_s)
        response.set_header("X-Total-Pages", pagy.pages.to_s)
        records
      end
    end
  end
end
