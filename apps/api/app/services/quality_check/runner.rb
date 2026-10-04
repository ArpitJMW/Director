module QualityCheck
  # Task 6: the quality_check stage. Order of work:
  #   1. project setting (once; one LLM call)
  #   2. deterministic checks on every unit (no AI)
  #   3. one vision review per image unit
  #   4. targeted repair of failed units, bounded, then re-check each repaired unit
  # Never raises for a QA problem: an unavailable reviewer marks units
  # "unavailable" and the pipeline carries on. A 429 stops the run and says so.
  class Runner

    def initialize(project:, gen_job: nil, reviewer: Providers.qa)
      @project = project
      @gen_job = gen_job
      @reviewer = reviewer
    end

    def call
      summary = { units: 0, passed: 0, failed: 0, unavailable: 0, skipped_quota: 0, repaired: 0, repairs_skipped: 0, stopped: nil }
      setting = ensure_setting
      summary[:setting] = setting.present?

      by_unit = Deterministic.new(@project).call.group_by { |i| i[:unit_key] }
      units = all_units
      summary[:units] = units.size

      # Image units with a current cached verdict reuse it. The rest are reviewed
      # in batches, highest risk first (Task 6.2 Part 0a).
      reviews = {}
      to_review = []
      units.each do |scene, shot|
        next unless image_unit?(scene, shot)

        unit = shot || scene
        if (prior = Store.reusable_vision(unit))
          reviews[unit.key] = VisionReview::Review.new(status: prior["status"],
                                                       issues: prior["issues"].to_a.map(&:symbolize_keys), error: nil)
        else
          risk = by_unit.fetch(unit.key, []).count { |i| blocking?(i) }
          to_review << BatchReview::Unit.new(key: unit.key, scene: scene, shot: shot, asset: unit.selected_asset, risk: risk)
        end
      end
      if to_review.any?
        batch = BatchReview.new(project: @project, reviewer: @reviewer).call(to_review)
        reviews.merge!(batch[:reviews])
        summary[:vision_calls] = batch[:calls]
      end

      units.each do |scene, shot|
        unit = shot || scene
        issues = by_unit.fetch(unit.key, [])
        review = reviews[unit.key]
        review_status = review&.status
        if review
          issues += review.issues
        end
        vision = review && !Store.reusable_vision(unit) && review.status != BatchReview::SKIPPED ? vision_record(unit, review) : nil
        status = if review_status == BatchReview::SKIPPED && !Verdict.failing?(issues)
                   BatchReview::SKIPPED
                 else
                   status_for(issues, review_status)
                 end
        Store.write(unit, status: status, issues: issues, vision: vision)
      end

      failed = all_units.select { |scene, shot| Store.read(shot || scene).to_h["status"] == "failed" }
      repairer = Repair.new(project: @project)
      failed.sort_by { |scene, shot| severity_rank(Store.read(shot || scene)) }.each do |scene, shot|
        unit = shot || scene
        issues = Store.read(unit)["issues"].select { |i| blocking?(i) }
        result = repairer.call(unit: unit, scene: scene, shot: shot, issues: issues.map(&:symbolize_keys))
        record_repair(unit, scene, shot, result, summary)
      end

      tally(summary)
      summary
    rescue Repair::Stop, Providers::Qa::GeminiVisionAdapter::RateLimited => e
      summary[:stopped] = "rate_limited: #{e.message.to_s.truncate(120)}"
      tally(summary)
      summary
    end

    private

    def ensure_setting
      Ai::SettingService.new(project: @project).call.presence
    rescue => e
      GenerationLog.create!(project: @project, generation_job: @gen_job, level: "warn", stage: "quality_check",
                            message: "setting unavailable — #{e.message.to_s.truncate(160)}")
      nil
    end

    # Every scene (it can carry scene-level issues such as missing audio) and
    # every shot, as [scene, shot-or-nil] pairs.
    def all_units
      @project.scenes.includes(:shots, :selected_asset).order(:position).flat_map do |scene|
        shots = scene.shots.to_a
        shots.empty? ? [ [ scene, nil ] ] : [ [ scene, nil ] ] + shots.map { |shot| [ scene, shot ] }
      end
    end

    def image_unit?(scene, shot)
      return false unless scene.asset_strategy == "image"
      return shot.present? ? shot.selected_asset.present? : (scene.shots.none? && scene.selected_asset.present?)
    end

    # A repair targets the issues that drove the failure: high and medium.
    def blocking?(issue)
      %w[high medium].include?(issue[:severity].to_s)
    end

    def status_for(issues, review_status)
      Verdict.status(issues, review_status: review_status)
    end

    def severity_rank(qa)
      issues = qa.to_h["issues"].to_a
      return 0 if issues.any? { |i| i["severity"] == "high" }
      return 1 if issues.any? { |i| i["severity"] == "medium" }

      2
    end

    def record_repair(unit, scene, shot, result, summary)
      previous = Store.repair_attempts(unit)
      record = { "attempts" => previous + 1, "outcome" => result[:outcome], "strategy" => result[:strategy],
                 "types" => result[:types], "brief" => result[:positive], "at" => Time.current.iso8601 }.compact
      if result[:outcome].start_with?("skipped")
        summary[:repairs_skipped] += 1
        return
      end

      final = result[:outcome]
      if result[:outcome] == "repaired"
        status = reissue(unit, scene, shot, result[:types], result[:strategy])
        # A repair only counts as a repair when the re-check now passes.
        final = status == "passed" ? "repaired" : "attempted_still_failing"
        summary[:repaired] += 1 if final == "repaired"
      end
      qa = Store.read(unit).to_h
      Store.write(unit, status: qa["status"], issues: qa["issues"].to_a, repair: record.merge("outcome" => final))
    end

    # Re-check the repaired unit with the same reviewer. Audio is re-checked by
    # the deterministic audio rule for that scene.
    # @return [String] the unit's status after the re-check. Text conversions
    # and audio repairs have no image to look at, so they are re-checked with
    # the deterministic rules. An image rewrite is re-reviewed by vision.
    def reissue(unit, scene, shot, types, strategy)
      remaining = Deterministic.new(@project).call.select { |i| i[:unit_key] == unit.key }
      unit.reload
      image_strategy = strategy.to_s.include?("prompt_rewrite")
      unless image_strategy
        status = status_for(remaining, nil)
        Store.write(unit, status: status, issues: remaining)
        return status
      end

      review = VisionReview.new(project: @project, scene: scene, shot: shot, reviewer: @reviewer).call(asset: unit.selected_asset)
      status = status_for(remaining + review.issues, review.status)
      Store.write(unit, status: status, issues: remaining + review.issues, vision: vision_record(unit, review))
      status
    end

    def vision_record(unit, review)
      { "asset_id" => unit.selected_asset&.public_id, "status" => review.status,
        "issues" => review.issues.map(&:stringify_keys) }
    end

    def tally(summary)
      all_units.each do |scene, shot|
        case Store.read(shot || scene).to_h["status"]
        when "passed" then summary[:passed] += 1
        when "failed" then summary[:failed] += 1
        when "unavailable" then summary[:unavailable] += 1
        when BatchReview::SKIPPED then summary[:skipped_quota] += 1
        end
      end
    end
  end
end
