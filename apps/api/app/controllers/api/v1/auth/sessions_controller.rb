module Api
  module V1
    module Auth
      class SessionsController < Devise::SessionsController
        private

        def respond_with(resource, _opts = {})
          render json: { user: UserSerializer.call(resource) }, status: :ok
        end

        # Called on sign_out. devise-jwt revokes the presented token via the
        # denylist before this runs.
        def respond_to_on_destroy
          if request.headers["Authorization"].present?
            render json: { message: "signed_out" }, status: :ok
          else
            render json: { error: "no_token" }, status: :unauthorized
          end
        end
      end
    end
  end
end
