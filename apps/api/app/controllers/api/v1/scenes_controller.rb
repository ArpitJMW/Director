module Api
  module V1
    class ScenesController < ResourceController
      before_action :set_scene, only: [ :show, :update ]

      # GET /api/v1/projects/:project_id/scenes
      def index
        project = Project.find_by_public_id!(params[:project_id])
        authorize project, :show?
        scenes = policy_scope(Scene).where(project: project).order(:position)
        render json: { scenes: SceneSerializer.list(scenes.includes(:project, :selected_asset)) }
      end

      def show
        authorize @scene
        render json: { scene: SceneSerializer.call(@scene) }
      end

      # Creator scene corrections (spec §10 — storyboard editor). Regeneration of
      # AI content is a Phase 3 pipeline action.
      def update
        authorize @scene
        @scene.update!(scene_params)
        render json: { scene: SceneSerializer.call(@scene) }
      end

      private

      def set_scene
        @scene = Scene.find_by_public_id!(params[:id])
      end

      def scene_params
        params.require(:scene).permit(
          :narration, :visual_type, :visual_prompt, :caption, :animation,
          :transition, :duration_seconds, :background_music_level, :notes
        )
      end
    end
  end
end
