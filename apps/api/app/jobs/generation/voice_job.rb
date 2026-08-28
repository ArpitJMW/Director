module Generation
  # Stage: narration + timed captions for every scene (spec §20 steps 11-12).
  # Per-scene failures don't abort the batch (spec §28); scenes that already have
  # a succeeded voice generation are skipped on retry.
  class VoiceJob < BaseJob
    sidekiq_options queue: "media"

    def run(gen_job)
      project = gen_job.project
      generated = 0
      failures = []

      project.scenes.each do |scene|
        service = Media::VoiceGenerationService.new(scene: scene)
        next unless service.generatable?
        next if scene.current_voice_generation&.status == "succeeded" &&
                scene.current_voice_generation.text == scene.narration

        begin
          service.call
          generated += 1
        rescue => e
          failures << { scene: scene.key, error: e.message }
          GenerationLog.create!(
            project: project, generation_job: gen_job, scene: scene, level: "error",
            stage: "voice", message: "scene #{scene.key}: #{e.message}"
          )
        end
      end

      gen_job.update!(result: { generated: generated, failures: failures })
      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info",
        stage: "voice", message: "Narrated #{generated} scenes (#{failures.size} failed)"
      )

      # Partial failure (e.g. provider rate limit) keeps the scenes that worked
      # and stays retryable per-scene (spec §28). Only a total wipeout fails the
      # stage.
      raise "all #{failures.size} scene(s) failed narration" if generated.zero? && failures.any?
    end
  end
end
