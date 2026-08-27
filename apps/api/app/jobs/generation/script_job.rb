module Generation
  # Stage: script generation (spec §20 step 5, §22).
  class ScriptJob < BaseJob
    sidekiq_options queue: "script"

    def run(gen_job)
      script = Ai::ScriptService.new(project: gen_job.project).call
      gen_job.update!(result: { script_id: script.public_id, script_version: script.version })
      GenerationLog.create!(
        project: gen_job.project, generation_job: gen_job, level: "info",
        stage: "script", message: "Generated script v#{script.version}"
      )
    end
  end
end
