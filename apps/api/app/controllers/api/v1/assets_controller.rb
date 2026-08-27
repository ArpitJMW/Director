module Api
  module V1
    class AssetsController < ResourceController
      # GET /api/v1/assets?project_id=proj_...&type=image
      def index
        assets = policy_scope(Asset).includes(:project, :scene).order(created_at: :desc)

        if params[:project_id].present?
          project = Project.find_by_public_id!(params[:project_id])
          assets = assets.where(project_id: project.id)
        end
        assets = assets.where(asset_type: params[:type]) if params[:type].present?

        render json: { assets: AssetSerializer.list(paginate(assets)) }
      end
    end
  end
end
