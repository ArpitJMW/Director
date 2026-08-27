module Api
  module V1
    class GenerationJobsController < ResourceController
      # GET /api/v1/projects/:project_id/jobs?active=true
      def index
        project = Project.find_by_public_id!(params[:project_id])
        authorize project, :show?

        jobs = policy_scope(GenerationJob).where(project: project).recent
        jobs = jobs.active if params[:active].present?
        jobs = jobs.limit(50)

        render json: { jobs: GenerationJobSerializer.list(jobs) }
      end
    end
  end
end
