module Generation
  # Stage: AI QA (Task 6). Runs after assets and voice, before the review
  # checkpoint. Records issues on each unit and repairs failed ones, bounded.
  # Never fails the stage for a QA problem, so render is never blocked by it.
  class QualityCheckJob < BaseJob
    sidekiq_options queue: "policy"

    def run(gen_job)
      summary = QualityCheck::Runner.new(project: gen_job.project, gen_job: gen_job).call
      gen_job.update!(result: summary)
      GenerationLog.create!(
        project: gen_job.project, generation_job: gen_job, level: summary[:stopped] ? "warn" : "info",
        stage: "quality_check",
        message: "QA: #{summary[:passed]} passed, #{summary[:failed]} failed, #{summary[:unavailable]} unavailable, " \
                 "#{summary[:repaired]} repaired (#{summary[:repairs_skipped]} skipped by limits)" \
                 "#{summary[:stopped] ? " — stopped: #{summary[:stopped]}" : ''}"
      )
    end
  end
end
