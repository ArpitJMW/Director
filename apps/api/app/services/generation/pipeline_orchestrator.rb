module Generation
  # Drives the auto-running pipeline (spec §20). Each stage job calls #advance on
  # success; the orchestrator enqueues the next stage or pauses at a review
  # checkpoint. In "manual" mode it does nothing (legacy per-button behaviour).
  module PipelineOrchestrator
    module_function

    # Ordered stages: [stage name, job class, project AASM event to enter it].
    STAGES = [
      [ "script",     ScriptJob,     :start_script! ],
      [ "storyboard", StoryboardJob, :start_storyboard! ],
      [ "assets",     AssetsJob,     :start_assets! ],
      [ "voice",      VoiceJob,      :start_voice! ],
      [ "preflight",  PreflightJob,  nil ],
      [ "render",     RenderJob,     :start_render! ]
    ].freeze

    # After these stages the pipeline pauses for a human checkpoint.
    CHECKPOINT_AFTER = { "assets" => "storyboard", "render" => "review" }.freeze
    CHECKPOINT_STAGE = CHECKPOINT_AFTER.invert.freeze

    def stage_names = STAGES.map(&:first)

    # Begin (or resume) an auto run — picks up wherever the project already is
    # so re-running doesn't throw away existing work.
    def start(project)
      project.update!(pipeline_mode: "auto", pipeline_checkpoint: nil, failure_reason: nil)

      if project.scenes.exists?
        project.update!(pipeline_checkpoint: "storyboard")
        nil
      elsif project.current_script.present?
        enqueue(project, "storyboard")
      else
        enqueue(project, "script")
      end
    end

    # Resume after a checkpoint the user has approved. At the final ("review")
    # checkpoint there is nothing left to run — the project is done.
    def continue(project)
      checkpoint = project.pipeline_checkpoint
      return false unless checkpoint

      project.update!(pipeline_checkpoint: nil)
      nxt = stage_after(CHECKPOINT_STAGE.fetch(checkpoint))
      if nxt
        enqueue(project, nxt)
      else
        project.complete! if project.may_complete?
      end
      true
    end

    # Send a finished/paused project back to the storyboard checkpoint so the
    # user can edit scenes and re-run the back half.
    def revise(project)
      project.update!(pipeline_mode: "auto", pipeline_checkpoint: "storyboard", failure_reason: nil)
    end

    # Called by BaseJob after a stage succeeds.
    def advance(project, completed_stage)
      return unless project.pipeline_mode == "auto"
      return if project.pipeline_checkpoint # already paused

      if (checkpoint = CHECKPOINT_AFTER[completed_stage])
        project.update!(pipeline_checkpoint: checkpoint)
        return
      end

      nxt = stage_after(completed_stage)
      enqueue(project, nxt) if nxt
    end

    # Creates the GenerationJob, advances project state, and enqueues the worker.
    # Shared by the orchestrator and the manual per-stage endpoints.
    def enqueue(project, stage)
      _name, job_class, event = STAGES.find { |s| s.first == stage }
      raise ArgumentError, "unknown stage #{stage.inspect}" unless job_class

      active = project.generation_jobs.active.where(scene_id: nil).find_by(stage: stage)
      return active if active

      gen_job = project.generation_jobs.create!(
        stage: stage, queue: job_class.sidekiq_options["queue"] || "default"
      )
      if event
        guard = "may_#{event.to_s.delete_suffix('!')}?"
        project.public_send(event) if project.public_send(guard)
      end
      gen_job.enqueue!
      job_class.perform_async(gen_job.id)
      gen_job
    end

    def stage_after(stage)
      names = stage_names
      idx = names.index(stage)
      idx && names[idx + 1]
    end
  end
end
