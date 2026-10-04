module Generation
  # Stage: generate visual assets (planning-doc §7, spec §20 step 10). Generates
  # one unit per SHOT when a scene has shots, otherwise one per scene, routed
  # through Media::ProductionDispatcher so each unit's asset_strategy decides
  # what actually gets produced (image, text animation spec, ...). Per-unit
  # failures don't abort the rest (spec §28); already-ready units are skipped so
  # retries only redo what failed. `force` redoes everything.
  class AssetsJob < BaseJob
    sidekiq_options queue: "media"

    def run(gen_job)
      project = gen_job.project
      force = gen_job.args["force"]
      log_estimate(project, gen_job)

      generated = 0
      failures = []

      project.scenes.includes(:shots).order(:position).each do |scene|
        units = scene.shots.order(:position).to_a
        units = [ scene ] if units.empty?

        units.each do |unit|
          next if !force && unit.status == "ready"

          shot = unit.is_a?(Shot) ? unit : nil
          service = Media::ProductionDispatcher.for(scene: scene, shot: shot)

          unless service.generatable?
            # Never leave a unit silently "pending" — a not-generatable unit
            # (e.g. no visual_prompt) won't become generatable on a Sidekiq
            # retry, so it's marked failed and logged here rather than
            # counted toward the all-failed raise below.
            label = shot ? shot.key : scene.key
            reason = "no producible content (asset_strategy=#{unit.asset_strategy.inspect}, " \
                     "visual_type=#{unit.visual_type.inspect})"
            unit.update(status: "failed", failure_reason: reason)
            GenerationLog.create!(
              project: project, generation_job: gen_job, scene: scene, level: "warn",
              stage: "assets", message: "#{label}: #{reason}"
            )
            next
          end

          begin
            service.call
            generated += 1
          rescue => e
            label = shot ? shot.key : scene.key
            failures << { unit: label, error: e.message }
            GenerationLog.create!(
              project: project, generation_job: gen_job, scene: scene, level: "error",
              stage: "assets", message: "#{label}: #{e.message}"
            )
          end
        end
      end

      gen_job.update!(result: { generated: generated, failures: failures })
      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info",
        stage: "assets", message: "Generated #{generated} unit(s) (#{failures.size} failed)"
      )

      raise "all #{failures.size} unit(s) failed generation" if generated.zero? && failures.any?
    end

    private

    def log_estimate(project, gen_job)
      est = Providers::CostReport.estimate(project)[:image]
      message = if est[:blocked]
        "Assets estimate: BLOCKED — #{est[:blocked]}"
      else
        "Assets estimate: #{est[:units]} image unit(s) × $#{format('%.3f', est[:rate_usd])} " \
          "(#{est[:provider]}/#{est[:model]}) ≈ $#{format('%.3f', est[:usd])}"
      end
      GenerationLog.create!(project: project, generation_job: gen_job, level: est[:blocked] ? "warn" : "info",
                            stage: "assets", message: message)
    end
  end
end
