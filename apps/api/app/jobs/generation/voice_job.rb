module Generation
  # Stage: narration + timed captions for every scene (spec §20 steps 11-12).
  # Per-scene failures don't abort the batch (spec §28); scenes that already have
  # a succeeded voice generation are skipped on retry.
  #
  # Phase 1 Task 2.4: when the configured voice provider supports batching
  # (Providers::Voice::Base#supports_batch?), every scene still needing audio
  # is routed through Media::BatchVoiceGenerationService — one provider call
  # instead of one per scene — because Gemini TTS's free tier returns 429
  # after ~1-2 per-scene calls. Providers that don't support it (or the fake
  # adapter used in tests) keep the original per-scene loop, unchanged.
  class VoiceJob < BaseJob
    sidekiq_options queue: "media"

    def run(gen_job)
      project = gen_job.project
      provider = Providers.voice

      pending = project.scenes.select { |scene| pending?(scene) }

      generated, failures =
        if provider.supports_batch?
          run_batch(project, provider, pending, gen_job)
        else
          run_per_scene(project, pending, gen_job)
        end

      gen_job.update!(result: { generated: generated, failures: failures })
      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info",
        stage: "voice", message: "Narrated #{generated} scenes (#{failures.size} failed)"
      )

      log_duration_drift(project, gen_job) if generated.positive?

      # Partial failure (e.g. provider rate limit) keeps the scenes that worked
      # and stays retryable per-scene (spec §28). Only a total wipeout fails the
      # stage.
      raise "all #{failures.size} scene(s) failed narration" if generated.zero? && failures.any?
    end

    private

    # Phase 1 Task 2.6: scene durations are now reconciled to real narration
    # length, so the total video length can end up longer or shorter than the
    # project's target. That's allowed (never speed up or cut audio to force
    # a match) — just log it so it's visible, not silently different.
    def log_duration_drift(project, gen_job)
      total = project.scenes.reload.sum { |s| s.duration_seconds.to_f }
      target = project.target_duration_seconds.to_f
      diff = total - target
      return if diff.abs < 1.0

      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info", stage: "voice",
        message: "video length is now #{total.round(1)}s vs target #{target.round(1)}s " \
                 "(#{diff.positive? ? '+' : ''}#{diff.round(1)}s) after reconciling scene durations to real narration"
      )
    end

    def pending?(scene)
      Media::VoiceGenerationService.new(scene: scene).generatable? &&
        !(scene.current_voice_generation&.status == "succeeded" &&
          scene.current_voice_generation.text == scene.narration)
    end

    def run_batch(project, provider, pending, gen_job)
      return [ 0, [] ] if pending.empty?

      begin
        succeeded = Media::BatchVoiceGenerationService.new(project: project, provider: provider, scenes: pending).call
        succeeded_ids = succeeded.map(&:scene_id)
        failures = pending.reject { |s| succeeded_ids.include?(s.id) }
          .map { |s| { scene: s.key, error: "no audio from the batch call" } }
        [ succeeded.size, failures ]
      rescue => e
        # Total wipeout (e.g. every chunk failed) — Media::BatchVoiceGenerationService
        # already logged the details; record it against every pending scene so
        # the stage's own failure accounting stays accurate.
        GenerationLog.create!(
          project: project, generation_job: gen_job, level: "error",
          stage: "voice", message: "batch voice: #{e.message}"
        )
        [ 0, pending.map { |s| { scene: s.key, error: e.message } } ]
      end
    end

    def run_per_scene(project, pending, gen_job)
      generated = 0
      failures = []

      pending.each do |scene|
        begin
          Media::VoiceGenerationService.new(scene: scene).call
          generated += 1
        rescue => e
          failures << { scene: scene.key, error: e.message }
          GenerationLog.create!(
            project: project, generation_job: gen_job, scene: scene, level: "error",
            stage: "voice", message: "scene #{scene.key}: #{e.message}"
          )
        end
      end

      [ generated, failures ]
    end
  end
end
