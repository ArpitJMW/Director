module Generation
  # Shared behaviour for pipeline jobs (spec §28). Each job is driven by a
  # GenerationJob row that tracks stage, attempts and status independently, so a
  # single failed stage never forces regeneration of the whole project.
  class BaseJob
    include Sidekiq::Job

    sidekiq_options retry: 3

    # When Sidekiq gives up, mark our records failed and remember the stage so
    # the project can be resumed from it.
    sidekiq_retries_exhausted do |msg, error|
      gen_job = GenerationJob.find_by(id: msg["args"].first)
      next unless gen_job

      gen_job.update(failure_reason: error&.message, error: { class: error&.class&.name })
      gen_job.mark_failed! if gen_job.may_mark_failed?
      project = gen_job.project
      project.update!(pipeline_checkpoint: nil) if project.pipeline_mode == "auto"
      project.mark_failed! if project.may_mark_failed?
    end

    def perform(generation_job_id)
      @gen_job = GenerationJob.find(generation_job_id)
      return if @gen_job.succeeded? || @gen_job.cancelled?

      @gen_job.update!(sidekiq_jid: jid)
      @gen_job.start! if @gen_job.may_start?

      run(@gen_job)

      @gen_job.succeed! if @gen_job.may_succeed?

      # Auto-run: chain to the next stage or pause at a review checkpoint.
      Generation::PipelineOrchestrator.advance(@gen_job.project.reload, @gen_job.stage)
    rescue => e
      @gen_job&.update(failure_reason: e.message, error: { class: e.class.name })
      GenerationLog.create!(
        project: @gen_job&.project, generation_job: @gen_job, level: "error",
        stage: @gen_job&.stage, message: e.message
      )
      raise
    end

    # Subclasses implement the actual work.
    def run(_gen_job)
      raise NotImplementedError
    end
  end
end
