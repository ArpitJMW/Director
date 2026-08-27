module Policy
  # spec §32 "Copyright/license metadata": licensed/stock assets must carry a
  # license string.
  module CopyrightChecker
    NEEDS_LICENSE = %w[licensed stock].freeze

    module_function

    def call(project:)
      missing = project.assets.select { |a| NEEDS_LICENSE.include?(a.source_type) && a.license.blank? }
      music_missing = project.music_tracks.select { |t| t.source_type != "public_domain" && t.license.blank? }

      warnings = []
      warnings << "#{missing.size} licensed/stock asset(s) have no license recorded." if missing.any?
      warnings << "#{music_missing.size} music track(s) have no license recorded." if music_missing.any?

      return CheckResult.pass("License metadata is complete.") if warnings.empty?

      CheckResult.warn("Some third-party media is missing license metadata.", warnings)
    end
  end
end
