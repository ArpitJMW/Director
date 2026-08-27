module Policy
  # spec §33: compare a new project against the creator's recent projects
  # (script similarity, scene count, template reuse, intro/outro patterns).
  module RepetitionChecker
    SIMILARITY_WARN = 0.55
    TEMPLATE_STREAK_WARN = 4
    RECENT_LIMIT = 10

    module_function

    def call(project:)
      others = project.user.projects
        .where.not(id: project.id)
        .where(status: %w[completed quality_check rendering])
        .order(created_at: :desc)
        .limit(RECENT_LIMIT)
        .includes(:current_script)
      return CheckResult.pass("No prior videos to compare against.") if others.empty?

      mine = shingles(narration_for(project))
      warnings = []

      most_similar = others.map { |o| [ o, jaccard(mine, shingles(narration_for(o))) ] }.max_by(&:last)
      if most_similar && most_similar.last >= SIMILARITY_WARN
        warnings << "Script is #{(most_similar.last * 100).round}% similar to \"#{most_similar.first.title}\"."
      end

      template_streak = others.take(TEMPLATE_STREAK_WARN - 1).count { |o| o.template_id && o.template_id == project.template_id }
      if project.template_id && template_streak >= TEMPLATE_STREAK_WARN - 1
        warnings << "The same template has been used for #{template_streak + 1} recent videos — vary the visual identity."
      end

      return CheckResult.pass("Distinct from recent videos.") if warnings.empty?

      CheckResult.warn("This video resembles recent uploads.", warnings)
    end

    def narration_for(project)
      project.current_script&.full_narration.presence ||
        project.scenes.map(&:narration).join(" ")
    end
    private_class_method :narration_for

    def shingles(text, size = 3)
      words = text.to_s.downcase.scan(/[a-z0-9']+/)
      return Set.new if words.size < size

      words.each_cons(size).map { |w| w.join(" ") }.to_set
    end
    private_class_method :shingles

    def jaccard(a, b)
      return 0.0 if a.empty? || b.empty?

      (a & b).size.to_f / (a | b).size
    end
    private_class_method :jaccard
  end
end
