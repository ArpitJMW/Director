module Api
  module V1
    class MeController < BaseController
      def show
        render json: { user: UserSerializer.call(current_user) }
      end

      def update
        current_user.update!(me_params)
        render json: { user: UserSerializer.call(current_user) }
      end

      private

      def me_params
        params.require(:user).permit(:name)
      end
    end
  end
end
