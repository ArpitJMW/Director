module Policy
  # spec §6, §27: every asset records where it came from.
  module ProvenanceChecker
    module_function

    def call(project:)
      assets = project.assets.to_a
      image_scenes = project.scenes.select { |s| Media::ImageGenerationService::IMAGE_TYPES.include?(s.visual_type) }
      missing_visuals = image_scenes.reject(&:selected_asset)

      warnings = []
      warnings << "#{missing_visuals.size} scene(s) have no visual asset: #{missing_visuals.map(&:key).join(', ')}." if missing_visuals.any?

      no_source = assets.select { |a| a.source_type.blank? || a.source_type == "other" }
      warnings << "#{no_source.size} asset(s) have an unspecified source type." if no_source.any?

      narrated = project.scenes.select { |s| s.narration.present? }
      unvoiced = narrated.reject { |s| s.current_voice_generation }
      warnings << "#{unvoiced.size} scene(s) have narration but no generated audio." if unvoiced.any?

      return CheckResult.pass("All assets have recorded provenance.") if warnings.empty?

      CheckResult.warn("Some assets or media are missing or lack provenance.", warnings)
    end
  end
end
