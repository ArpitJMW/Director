module Api
  module V1
    # Long-running generation actions (spec §28). Each returns 202 with a
    # GenerationJob to poll; the work runs in Sidekiq.
    class PipelineController < ResourceController
      # POST /api/v1/projects/:id/script/generate
      def generate_script
        start_stage(
          stage: "script",
          job: Generation::ScriptJob,
          allowed: -> { _1.script_generating? || _1.may_start_script? },
          advance: :start_script!,
          may_advance: :may_start_script?
        )
      end

      # POST /api/v1/projects/:id/storyboard/generate
      def generate_storyboard
        start_stage(
          stage: "storyboard",
          job: Generation::StoryboardJob,
          allowed: -> { _1.current_script.present? && (_1.storyboarding? || _1.may_start_storyboard?) },
          advance: :start_storyboard!,
          may_advance: :may_start_storyboard?,
          precondition_message: "Generate a script first."
        )
      end

      # POST /api/v1/projects/:id/assets/generate
      def generate_assets
        start_stage(
          stage: "assets",
          job: Generation::AssetsJob,
          allowed: -> { _1.scenes.exists? && (_1.generating_assets? || _1.may_start_assets?) },
          advance: :start_assets!,
          may_advance: :may_start_assets?,
          precondition_message: "Generate a storyboard first."
        )
      end

      # POST /api/v1/projects/:id/voice/generate
      def generate_voice
        start_stage(
          stage: "voice",
          job: Generation::VoiceJob,
          allowed: -> { _1.scenes.where.not(narration: [ nil, "" ]).exists? && (_1.generating_voice? || _1.may_start_voice?) },
          advance: :start_voice!,
          may_advance: :may_start_voice?,
          precondition_message: "Generate a storyboard first."
        )
      end

      # POST /api/v1/scenes/:id/assets/regenerate
      def regenerate_scene_asset
        scene = scene_scope
        project = scene.project
        authorize project, :generate?

        existing = project.generation_jobs.active.find_by(stage: "assets", scene_id: scene.id)
        if existing
          return render json: { job: GenerationJobSerializer.call(existing) }, status: :accepted
        end

        gen_job = project.generation_jobs.create!(stage: "assets", queue: "media", scene: scene)
        gen_job.enqueue!
        Generation::SceneAssetJob.perform_async(gen_job.id)

        render json: { job: GenerationJobSerializer.call(gen_job.reload) }, status: :accepted
      end

      # POST /api/v1/projects/:id/render
      def render_video
        start_stage(
          stage: "render",
          job: Generation::RenderJob,
          allowed: -> { _1.scenes.exists? && (_1.rendering? || _1.may_start_render?) },
          advance: :start_render!,
          may_advance: :may_start_render?,
          precondition_message: "Generate a storyboard first."
        )
      end

      def regenerate_scene = not_implemented(scene_scope, "scene regeneration")

      private

      def start_stage(stage:, job:, allowed:, advance:, may_advance:, precondition_message: nil)
        project = project_scope
        authorize project, :generate?

        return render_invalid_state(project, precondition_message) unless allowed.call(project)

        existing = project.generation_jobs.active.where(scene_id: nil).find_by(stage: stage)
        if existing
          return render json: { job: GenerationJobSerializer.call(existing) }, status: :accepted
        end

        gen_job = project.generation_jobs.create!(stage: stage, queue: job.sidekiq_options["queue"] || "default")
        project.public_send(advance) if project.public_send(may_advance)
        gen_job.enqueue!
        job.perform_async(gen_job.id)

        render json: {
          job: GenerationJobSerializer.call(gen_job.reload),
          project: ProjectSerializer.call(project)
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
        render json: {
          error: "not_implemented",
          message: "#{label.capitalize} is not available yet.",
          available_in: "Phase 3+ — AI pipeline"
        }, status: :not_implemented
      end
    end
  end
end
