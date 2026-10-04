module Generation
  # Stage: run the YouTube preflight (spec §20 step 17, §32).
  #
  # Task 4.3 Part 5: every "continue" from the review checkpoint (including a
  # retry-from-here after an unrelated render failure) used to re-run this
  # unconditionally, unlike VoiceJob's own already-succeeded-and-unchanged
  # skip. Preflight has no single "did the input change" field the way a
  # scene's narration text is for voice, so the same guard is expressed here
  # against the timestamps of everything the checks actually read (spec §32:
  # scenes, the current script, assets) — no new column/migration needed.
  class PreflightJob < BaseJob
    sidekiq_options queue: "policy"

    def run(gen_job)
      project = gen_job.project

      if (report = current_report(project))
        gen_job.update!(result: { preflight_report_id: report.public_id, status: report.status, skipped: true })
        GenerationLog.create!(
          project: project, generation_job: gen_job, level: "info", stage: "preflight",
          message: "Preflight: reused #{report.public_id} (#{report.status}) — no scene/script/asset " \
                    "changed since it was generated"
        )
        return
      end

      report = Policy::PreflightEngine.new(project: project).call
      gen_job.update!(result: { preflight_report_id: report.public_id, status: report.status })
      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info",
        stage: "preflight", message: "Preflight: #{report.status} (#{report.warnings.size} warnings)"
      )
    end

    private

    # The most recent report, if nothing the checks read has changed since it
    # ran — mirrors VoiceJob#pending?'s "already succeeded and input
    # unchanged" guard, just built from timestamps instead of a stored
    # fingerprint (PreflightReport keeps no single "input" column to compare,
    # unlike VoiceGeneration#text).
    def current_report(project)
      report = project.preflight_reports.order(:created_at).last
      return nil unless report

      latest_input_change = [
        project.scenes.maximum(:updated_at),
        project.current_script&.updated_at,
        project.assets.maximum(:updated_at)
      ].compact.max

      report if latest_input_change.nil? || latest_input_change <= report.created_at
    end
  end
end
