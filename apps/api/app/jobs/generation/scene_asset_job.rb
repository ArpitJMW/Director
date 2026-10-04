module Generation
  # Regenerate the visuals for a single scene (spec §29
  # POST /scenes/:id/assets/regenerate). Redoes every unit of the scene — each
  # shot, or the scene itself when it has no shots — via
  # Media::ProductionDispatcher, so a text-strategy scene regenerates its text
  # spec exactly as an image-strategy scene regenerates its image. The
  # GenerationJob carries the scene.
  class SceneAssetJob < BaseJob
    sidekiq_options queue: "media"

    def run(gen_job)
      scene = gen_job.scene
      raise "generation job has no scene" if scene.nil?

      targets = scene.shots.order(:position).to_a.presence || [ scene ]
      previous = targets.filter_map(&:selected_asset)

      produced = 0
      targets.each do |unit|
        shot = unit.is_a?(Shot) ? unit : nil
        service = Media::ProductionDispatcher.for(scene: scene, shot: shot)

        unless service.generatable?
          # Never leave a unit silently "pending" — see the identical note in
          # Generation::AssetsJob.
          label = shot ? shot.key : scene.key
          reason = "no producible content (asset_strategy=#{unit.asset_strategy.inspect}, " \
                   "visual_type=#{unit.visual_type.inspect})"
          unit.update(status: "failed", failure_reason: reason)
          GenerationLog.create!(
            project: scene.project, generation_job: gen_job, scene: scene, level: "warn",
            stage: "assets", message: "#{label}: #{reason}"
          )
          next
        end

        service.call
        produced += 1
      end
      raise "scene #{scene.key} has no producible visuals" if produced.zero?

      # Drop assets that were selected before this run and aren't selected now
      # (storage purged by an Asset callback). No-op for text units, which
      # never select an asset.
      current = targets.filter_map { |u| u.reload.selected_asset }
      previous.each { |a| a.destroy if current.exclude?(a) }

      gen_job.update!(result: { scene: scene.key, produced: produced })
    end
  end
end
