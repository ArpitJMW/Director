module Api
  module V1
    class AssetsController < ResourceController
      MAX_UPLOAD_BYTES = 50.megabytes
      ALLOWED_TYPES = %w[
        image/png image/jpeg image/webp image/gif
        video/mp4 video/webm audio/mpeg audio/wav audio/mp4
      ].freeze

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

      # POST /api/v1/projects/:project_id/assets  (multipart: file, asset_type, scene_id?)
      def create
        project = Project.find_by_public_id!(params[:project_id])
        authorize project, :update?

        file = params[:file]
        return render_error("file is required") if file.blank?
        return render_error("unsupported content type: #{file.content_type}") unless ALLOWED_TYPES.include?(file.content_type)
        return render_error("file too large (max 50 MB)") if file.size > MAX_UPLOAD_BYTES

        scene = project.scenes.find_by_public_id!(params[:scene_id]) if params[:scene_id].present?

        asset = Asset.store!(
          project: project, scene: scene,
          asset_type: params[:asset_type].presence || infer_type(file.content_type),
          io: file.tempfile, content_type: file.content_type,
          source_type: "user_provided", ai_generated: false
        )

        render json: { asset: AssetSerializer.call(asset) }, status: :created
      end

      private

      def infer_type(content_type)
        return "image" if content_type.start_with?("image/")
        return "video" if content_type.start_with?("video/")

        "audio"
      end

      def render_error(message)
        render json: { error: "unprocessable_content", messages: [ message ] }, status: :unprocessable_content
      end
    end
  end
end
