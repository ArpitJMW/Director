module Api
  module V1
    # Long-running generation actions (spec §28). Each returns 202 with a
    # GenerationJob to poll; the work runs in Sidekiq.
    class PipelineController < ResourceController
      # POST /api/v1/projects/:id/script/generate
      def generate_script
        project = project_scope
        authorize project, :generate?

        unless project.script_generating? || project.may_start_script?
          return render_invalid_state(project)
        end

        existing = project.generation_jobs.active.find_by(stage: "script")
        return render_job(existing, status: :accepted) if existing

        gen_job = project.generation_jobs.create!(stage: "script", queue: "script")
        project.start_script! if project.may_start_script?
        gen_job.enqueue!
        Generation::ScriptJob.perform_async(gen_job.id)

        render json: {
          job: GenerationJobSerializer.call(gen_job.reload),
          project: ProjectSerializer.call(project)
        }, status: :accepted
      end

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

      def render_job(job, status:)
        render json: { job: GenerationJobSerializer.call(job) }, status: status
      end

      def render_invalid_state(project)
        render json: {
          error: "invalid_state",
          message: "Cannot start script generation from status '#{project.status}'.",
          status: project.status
        }, status: :conflict
      end

      def not_implemented(record, label)
        authorize record, :generate?
        render json: {
          error: "not_implemented",
          message: "#{label.capitalize} is not available yet.",
          available_in: "Phase 3+ — AI pipeline"
        }, status: :not_implemented
      end
    end
  end
end
