module Policy
  # spec §6, §21: avoid workflows that copy source text into the narration
  # without substantive transformation.
  module ReuseChecker
    NGRAM = 8            # consecutive-word run considered "verbatim"
    MAX_VERBATIM_RUNS = 2

    module_function

    def call(project:)
      sources = project.sources.where.not(raw_excerpt: [ nil, "" ]).to_a
      return CheckResult.pass("No source text to compare against.") if sources.empty?

      narration = RepetitionChecker.send(:narration_for, project).downcase
      narration_ngrams = ngrams(narration)

      hits = sources.flat_map do |source|
        ngrams(source.raw_excerpt.to_s.downcase).select { |g| narration_ngrams.include?(g) }
      end.uniq

      return CheckResult.pass("Narration is a synthesis, not a copy.") if hits.size <= MAX_VERBATIM_RUNS

      CheckResult.warn(
        "Narration reuses phrasing from the research sources.",
        "#{hits.size} verbatim runs of #{NGRAM}+ words match source text — rewrite in your own words."
      )
    end

    def ngrams(text)
      words = text.scan(/[a-z0-9']+/)
      return Set.new if words.size < NGRAM

      words.each_cons(NGRAM).map { |w| w.join(" ") }.to_set
    end
    private_class_method :ngrams
  end
end
