module Generation
  # Regenerate the image for a single scene (spec §29
  # POST /scenes/:id/assets/regenerate). The GenerationJob carries the scene.
  class SceneAssetJob < BaseJob
    sidekiq_options queue: "media"

    def run(gen_job)
      scene = gen_job.scene
      raise "generation job has no scene" if scene.nil?

      previous = scene.selected_asset
      asset = Media::ImageGenerationService.new(scene: scene).call
      raise "scene #{scene.key} is not an image scene" if asset.nil?

      # Drop the superseded asset (storage object purged by an Asset callback).
      previous&.destroy if previous && previous != asset

      gen_job.update!(result: { scene: scene.key, asset_id: asset.public_id })
    end
  end
end
