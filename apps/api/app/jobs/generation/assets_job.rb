module Generation
  # Stage: generate visual assets for every scene (spec §20 step 10). Per-scene
  # failures do not abort the others (spec §28); already-ready scenes are skipped
  # so retries only redo what failed.
  class AssetsJob < BaseJob
    sidekiq_options queue: "media"

    def run(gen_job)
      project = gen_job.project
      scenes = project.scenes.where.not(status: "ready")

      generated = 0
      failures = []

      scenes.each do |scene|
        service = Media::ImageGenerationService.new(scene: scene)
        next unless service.generatable?

        begin
          service.call
          generated += 1
        rescue => e
          failures << { scene: scene.key, error: e.message }
          GenerationLog.create!(
            project: project, generation_job: gen_job, scene: scene, level: "error",
            stage: "assets", message: "scene #{scene.key}: #{e.message}"
          )
        end
      end

      gen_job.update!(result: { generated: generated, failures: failures })
      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info",
        stage: "assets", message: "Generated #{generated} images (#{failures.size} failed)"
      )

      # Partial failure keeps the images that worked; a scene stays retryable on
      # its own (spec §28). Only a total wipeout fails the stage.
      raise "all #{failures.size} scene(s) failed image generation" if generated.zero? && failures.any?
    end
  end
end
