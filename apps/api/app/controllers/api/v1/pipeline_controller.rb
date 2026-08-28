module Api
  module V1
    # Generation actions (spec §20, §28). Each returns 202 with a GenerationJob
    # to poll; work runs in Sidekiq. In "auto" mode the pipeline chains stages
    # itself (Generation::PipelineOrchestrator) and only these endpoints are
    # needed: pipeline/start, pipeline/continue, and the per-scene regenerate
    # actions. The per-stage endpoints remain for manual / re-run use.
    class PipelineController < ResourceController
      # POST /api/v1/projects/:id/pipeline/start
      def pipeline_start
        project = project_scope
        authorize project, :generate?

        gen_job = Generation::PipelineOrchestrator.start(project)
        render json: {
          job: GenerationJobSerializer.call(gen_job),
          project: ProjectSerializer.call(project.reload)
        }, status: :accepted
      end

      # POST /api/v1/projects/:id/pipeline/continue  (approve a review checkpoint)
      def pipeline_continue
        project = project_scope
        authorize project, :generate?

        unless project.pipeline_checkpoint
          return render json: { error: "not_paused", message: "The pipeline is not waiting at a checkpoint." }, status: :conflict
        end

        Generation::PipelineOrchestrator.continue(project)
        render json: { project: ProjectSerializer.call(project.reload) }, status: :accepted
      end

      # POST /api/v1/projects/:id/pipeline/revise  (go back to storyboard editing)
      def pipeline_revise
        project = project_scope
        authorize project, :generate?
        return render_invalid_state(project, "Generate a storyboard first.") unless project.scenes.exists?

        Generation::PipelineOrchestrator.revise(project)
        render json: { project: ProjectSerializer.call(project.reload) }, status: :accepted
      end

      def generate_script
        start_stage("script", allowed: -> { _1.script_generating? || _1.may_start_script? })
      end

      def generate_storyboard
        start_stage("storyboard",
          allowed: -> { _1.current_script.present? && (_1.storyboarding? || _1.may_start_storyboard?) },
          precondition_message: "Generate a script first.")
      end

      def generate_assets
        start_stage("assets",
          allowed: -> { _1.scenes.exists? && (_1.generating_assets? || _1.may_start_assets?) },
          precondition_message: "Generate a storyboard first.")
      end

      def generate_voice
        start_stage("voice",
          allowed: -> { _1.scenes.where.not(narration: [ nil, "" ]).exists? && (_1.generating_voice? || _1.may_start_voice?) },
          precondition_message: "Generate a storyboard first.")
      end

      def render_video
        start_stage("render",
          allowed: -> { _1.scenes.exists? && (_1.rendering? || _1.may_start_render?) },
          precondition_message: "Generate a storyboard first.")
      end

      def generate_preflight
        start_stage("preflight",
          allowed: -> { _1.scenes.exists? },
          precondition_message: "Generate a storyboard first.")
      end

      # POST /api/v1/scenes/:id/assets/regenerate
      def regenerate_scene_asset
        scene = scene_scope
        project = scene.project
        authorize project, :generate?

        existing = project.generation_jobs.active.find_by(stage: "assets", scene_id: scene.id)
        return render json: { job: GenerationJobSerializer.call(existing) }, status: :accepted if existing

        gen_job = project.generation_jobs.create!(stage: "assets", queue: "media", scene: scene)
        gen_job.enqueue!
        Generation::SceneAssetJob.perform_async(gen_job.id)
        render json: { job: GenerationJobSerializer.call(gen_job.reload) }, status: :accepted
      end

      # POST /api/v1/projects/:id/preflight/acknowledge
      def acknowledge_preflight
        project = project_scope
        authorize project, :generate?

        report = project.preflight_reports.order(created_at: :desc).first
        return head :not_found if report.nil?

        report.acknowledge!(current_user)
        render json: { preflight: PreflightReportSerializer.call(report) }
      end

      def regenerate_scene = not_implemented(scene_scope, "scene regeneration")

      private

      def start_stage(stage, allowed:, precondition_message: nil)
        project = project_scope
        authorize project, :generate?

        return render_invalid_state(project, precondition_message) unless allowed.call(project)

        gen_job = Generation::PipelineOrchestrator.enqueue(project, stage)
        render json: {
          job: GenerationJobSerializer.call(gen_job),
          project: ProjectSerializer.call(project.reload)
        }, status: :accepted
      end

      def project_scope
        Project.find_by_public_id!(params[:project_id] || params[:id])
      end

      def scene_scope
        Scene.find_by_public_id!(params[:scene_id] || params[:id])
      end

      def render_invalid_state(project, message = nil)
        render json: {
          error: "invalid_state",
          message: message || "Cannot start this stage from status '#{project.status}'.",
          status: project.status
        }, status: :conflict
      end

      def not_implemented(record, label)
        authorize record, :generate?
        render json: { error: "not_implemented", message: "#{label.capitalize} is not available yet." }, status: :not_implemented
      end
    end
  end
end
