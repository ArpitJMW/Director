module Policy
  # spec §6: reject image-only/slideshow outputs with weak narration or
  # educational/entertainment value. Heuristic — narration density and coverage.
  module NarrativeValueChecker
    MIN_WORDS_PER_SECOND = 1.4
    MIN_WORDS_PER_SCENE = 8

    module_function

    def call(project:)
      scenes = project.scenes.to_a
      return CheckResult.warn("No scenes to evaluate.") if scenes.empty?

      total_words = scenes.sum { |s| s.narration.to_s.split.size }
      total_seconds = scenes.sum { |s| s.duration_seconds.to_f }
      density = total_seconds.zero? ? 0 : total_words / total_seconds

      thin = scenes.select { |s| s.narration.to_s.split.size < MIN_WORDS_PER_SCENE }

      warnings = []
      warnings << "Narration is sparse (#{density.round(1)} words/sec)." if density < MIN_WORDS_PER_SECOND
      warnings << "#{thin.size} scene(s) have little or no narration: #{thin.map(&:key).join(', ')}." if thin.any?

      return CheckResult.pass("#{total_words} words across #{scenes.size} scenes.") if warnings.empty?

      CheckResult.warn("Narration may be too thin to carry the video.", warnings)
    end
  end
end
