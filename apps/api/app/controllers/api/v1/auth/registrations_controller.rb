module Api
  module V1
    module Auth
      class RegistrationsController < Devise::RegistrationsController
        private

        def sign_up_params
          params.require(:user).permit(:name, :email, :password, :password_confirmation)
        end

        # Devise calls this after create. The JWT is added to the Authorization
        # response header by devise-jwt's dispatch hook.
        def respond_with(resource, _opts = {})
          if resource.persisted?
            render json: { user: UserSerializer.call(resource) }, status: :created
          else
            render json: {
              error: "unprocessable_entity",
              messages: resource.errors.full_messages
            }, status: :unprocessable_content
          end
        end
      end
    end
  end
end
