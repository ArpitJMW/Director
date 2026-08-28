module Api
  module V1
    class ProjectsController < ResourceController
      before_action :set_project, only: [ :show, :update, :destroy ]

      def index
        projects = policy_scope(Project).order(created_at: :desc)
        projects = paginate(projects.includes(:template))
        render json: { projects: ProjectSerializer.list(projects) }
      end

      def show
        authorize @project
        render json: { project: ProjectSerializer.call(@project, include_script: true, include_scenes: true) }
      end

      def create
        project = current_user.projects.new(project_params)
        authorize project
        project.save!
        render json: { project: ProjectSerializer.call(project) }, status: :created
      end

      def update
        authorize @project
        @project.update!(project_params)
        render json: { project: ProjectSerializer.call(@project) }
      end

      def destroy
        authorize @project
        @project.destroy!
        head :no_content
      end

      private

      def set_project
        @project = Project.find_by_public_id!(params[:id])
      end

      def project_params
        params.require(:project).permit(
          :title, :topic, :format, :aspect_ratio, :visual_style, :niche, :audience, :tone,
          :target_duration_seconds, :creator_instructions, :research_enabled,
          :template_id,
          settings: {}
        ).tap do |permitted|
          # Accept a template public_id and resolve it to the record.
          if permitted.key?(:template_id)
            template = permitted.delete(:template_id)
            permitted[:template] = template.present? ? Template.find_by_public_id!(template) : nil
          end
        end
      end
    end
  end
end
