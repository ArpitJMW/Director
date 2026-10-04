module QualityCheck
  # Task 6.2 Part 0a: vision review several images per request. Calls are the
  # scarce resource (Google's free tier is a daily request cap per key), so:
  #   * up to BATCH_SIZE images share one request;
  #   * a daily guard (QA_DAILY_CALL_LIMIT, default 20) counts every QA request
  #     made today across all projects, since the quota is per key;
  #   * when the guard is exhausted, the remaining units are marked
  #     "qa_skipped_quota" rather than failing the stage;
  #   * units are reviewed highest-risk first;
  #   * an image missing from a batch reply falls back to a single-image review.
  class BatchReview
    BATCH_SIZE = 6
    SKIPPED = "qa_skipped_quota".freeze

    Unit = Data.define(:key, :scene, :shot, :asset, :risk)

    def initialize(project:, reviewer:, daily_limit: ENV.fetch("QA_DAILY_CALL_LIMIT", "20").to_i)
      @project = project
      @reviewer = reviewer
      @daily_limit = daily_limit
    end

    # @param units [Array<Unit>]
    # @return [Hash] { reviews: { key => VisionReview::Review }, calls: n }
    def call(units)
      reviews = {}
      calls = 0
      ordered = units.sort_by { |u| [ -u.risk, u.scene.position ] }

      ordered.each_slice(BATCH_SIZE) do |chunk|
        if daily_calls_used >= @daily_limit
          chunk.each { |u| reviews[u.key] = skipped }
          next
        end

        results = review_chunk(chunk)
        calls += 1
        chunk.each do |unit|
          if results[unit.key]
            reviews[unit.key] = results[unit.key]
          elsif daily_calls_used < @daily_limit
            reviews[unit.key] = single(unit)
            calls += 1
          else
            reviews[unit.key] = skipped
          end
        end
      end

      { reviews: reviews, calls: calls }
    end

    # QA requests made today, across all projects.
    def daily_calls_used
      AiGeneration.where(kind: "quality_check", provider: @reviewer.name)
                  .where("created_at >= ?", Time.current.beginning_of_day).count
    end

    private

    # One request for the chunk. Returns { key => Review } for the ids the reply
    # covered; anything it did not cover is absent (the caller falls back).
    def review_chunk(chunk)
      prompt = Prompts.load("quality_check_batch")
      images = chunk.map { |u| { id: u.key, bytes: bytes_for(u.asset), content_type: u.asset.content_type || "image/jpeg" } }
      result = AiGeneration.track!(
        project: @project, scene: chunk.first.scene, kind: "quality_check", provider_kind: "llm",
        provider: @reviewer.name, model: @reviewer.default_model,
        request: { prompt_version: prompt.version, batch: chunk.map(&:key) }
      ) do |_gen|
        @reviewer.review_batch(images: images, prompt: batch_prompt(prompt.text, chunk))
      end
      parse_batch(result.text, chunk)
    rescue => e
      raise if e.is_a?(Providers::Qa::GeminiVisionAdapter::RateLimited) || e.message.to_s.include?("429")

      {}
    end

    def parse_batch(text, chunk)
      data = JSON.parse(text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, ""))
      list = data.is_a?(Hash) ? data["results"] : nil
      return {} unless list.is_a?(Array)

      by_id = list.select { |r| r.is_a?(Hash) }.index_by { |r| r["id"].to_s }
      chunk.each_with_object({}) do |unit, out|
        entry = by_id[unit.key]
        next unless entry && entry["issues"].is_a?(Array)

        vr = VisionReview.new(project: @project, scene: unit.scene, shot: unit.shot, reviewer: @reviewer)
        issues = entry["issues"].filter_map { |raw| vr.normalize(raw) }
        out[unit.key] = VisionReview::Review.new(status: Verdict.status(issues), issues: issues, error: nil)
      end
    rescue JSON::ParserError
      {}
    end

    def skipped
      VisionReview::Review.new(status: SKIPPED, issues: [], error: "daily QA limit reached")
    end

    def single(unit)
      VisionReview.new(project: @project, scene: unit.scene, shot: unit.shot, reviewer: @reviewer).call(asset: unit.asset)
    end

    def batch_prompt(template, chunk)
      context = chunk.map do |u|
        "Image id #{u.key}: narration \"#{u.scene.narration.to_s.truncate(200)}\"; action \"#{(u.shot&.action.presence || u.scene.action).to_s.truncate(160)}\"; setting #{setting_text}"
      end
      "#{template}\n\nCONTEXT PER IMAGE\n#{context.join("\n")}"
    end

    def setting_text
      s = (@project.settings || {})["setting"]
      s.is_a?(Hash) ? "#{s['era']}; #{s['place']}" : "(none set)"
    end

    def bytes_for(asset)
      File.binread(Rails.root.join("storage", "uploads", asset.storage_key).to_s)
    end
  end
end
