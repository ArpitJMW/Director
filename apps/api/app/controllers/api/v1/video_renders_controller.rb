module Api
  module V1
    class VideoRendersController < ResourceController
      # GET /api/v1/projects/:project_id/renders
      def index
        project = Project.find_by_public_id!(params[:project_id])
        authorize project, :show?
        renders = policy_scope(VideoRender)
          .where(project: project)
          .includes(:output_asset)
          .order(version: :desc)
        render json: { renders: VideoRenderSerializer.list(renders) }
      end
    end
  end
end
