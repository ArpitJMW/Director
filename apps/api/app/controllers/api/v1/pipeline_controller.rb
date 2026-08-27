module Api
  module V1
    # Long-running generation actions (spec §28). The endpoints and their
    # authorization exist now; the pipeline itself (provider adapters, Sidekiq
    # jobs) lands in Phase 3+. Until then these return 501 so clients can wire
    # the calls without guessing the shape.
    class PipelineController < ResourceController
      def generate_script        = not_implemented(project_scope, "script generation")
      def generate_storyboard    = not_implemented(project_scope, "storyboard generation")
      def render_video           = not_implemented(project_scope, "rendering")
      def regenerate_scene       = not_implemented(scene_scope, "scene regeneration")
      def regenerate_scene_asset = not_implemented(scene_scope, "scene asset regeneration")

      private

      def project_scope
        Project.find_by_public_id!(params[:project_id] || params[:id])
      end

      def scene_scope
        Scene.find_by_public_id!(params[:scene_id] || params[:id])
      end

      def not_implemented(record, label)
        authorize record, :generate?
        render json: {
          error: "not_implemented",
          message: "#{label.capitalize} is not available yet.",
          available_in: "Phase 3 — AI pipeline"
        }, status: :not_implemented
      end
    end
  end
end
