module Generation
  # Stage: run the YouTube preflight (spec §20 step 17, §32).
  class PreflightJob < BaseJob
    sidekiq_options queue: "policy"

    def run(gen_job)
      report = Policy::PreflightEngine.new(project: gen_job.project).call
      gen_job.update!(result: { preflight_report_id: report.public_id, status: report.status })
      GenerationLog.create!(
        project: gen_job.project, generation_job: gen_job, level: "info",
        stage: "preflight", message: "Preflight: #{report.status} (#{report.warnings.size} warnings)"
      )
    end
  end
end
