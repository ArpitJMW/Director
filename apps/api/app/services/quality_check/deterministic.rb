module QualityCheck
  # Task 6 Part A: checks that need no AI and always run. Each returns issues as
  # hashes { unit_key:, scene_key:, shot_key:, issue_type:, severity:, evidence:,
  # source: "deterministic" }. Severity "info" never fails a unit.
  class Deterministic
    # Narration counts as covered when measured speech is at least this share of
    # what the word count predicts (Task 6 A1).
    AUDIO_COVERAGE_MIN = 0.5

    def initialize(project)
      @project = project
    end

    def call
      @project.scenes.includes(:shots, :selected_asset, :voice_generations).order(:position).flat_map do |scene|
        scene_issues(scene) + unit_issues(scene)
      end
    end

    private

    def scene_issues(scene)
      issues = []
      if scene.visual_type == "chart" && scene.asset_strategy == "image"
        issues << issue(scene, nil, "chart_routed_to_image", "high",
                        "planned visual_type 'chart' reached the image model; a chart image carries invented numbers")
      end
      issues + audio_issues(scene)
    end

    def audio_issues(scene)
      return [] if scene.narration.blank?

      expected = scene.narration.split.size / Ai::ScriptService::MEASURED_WORDS_PER_SECOND
      voice = scene.current_voice_generation
      measured = voice&.status == "succeeded" ? voice.duration_seconds.to_f : 0.0
      return [] if measured >= expected * AUDIO_COVERAGE_MIN

      [ issue(scene, nil, "audio_missing", "high",
              "narration has #{scene.narration.split.size} words (~#{expected.round(1)}s of speech) " \
              "but measured audio is #{measured.round(2)}s") ]
    end

    def unit_issues(scene)
      units = scene.shots.to_a.presence || [ scene ]
      units.flat_map do |unit|
        shot = unit.is_a?(Shot) ? unit : nil
        next [] unless scene.asset_strategy == "image"

        asset = unit.selected_asset
        if asset.nil?
          [ issue(scene, shot, "missing_asset", "high", "image unit has no selected asset") ]
        else
          aspect_info(scene, shot, asset) + letterbox_issues(scene, shot, asset)
        end
      end
    end

    # Cover-fit in the renderer makes a 1:1 still safe for 16:9, so a mismatch is
    # reported as information only.
    def aspect_info(scene, shot, asset)
      return [] unless asset.width && asset.height

      target = @project.aspect_ratio.split(":").map(&:to_f).reduce(:/)
      actual = asset.width.to_f / asset.height
      return [] if (actual - target).abs / target <= 0.03

      [ issue(scene, shot, "aspect_mismatch", "info",
              "stored #{asset.width}x#{asset.height} is not #{@project.aspect_ratio}; renderer cover-fits it") ]
    end

    def letterbox_issues(scene, shot, asset)
      bytes = File.binread(Rails.root.join("storage", "uploads", asset.storage_key).to_s)
      result = Media::LetterboxCropper.new(aspect_ratio: @project.aspect_ratio)
                                      .call(bytes: bytes, content_type: asset.content_type || "image/jpeg")
      return [] unless result.cropped

      bars = result.info["bars"]
      [ issue(scene, shot, "letterbox", "medium",
              "black bars still present (top #{bars['top']}px, bottom #{bars['bottom']}px, " \
              "left #{bars['left']}px, right #{bars['right']}px)") ]
    rescue Errno::ENOENT, Media::LetterboxCropper::Error => e
      [ issue(scene, shot, "image_unreadable", "high", "stored image could not be read: #{e.message.to_s.truncate(120)}") ]
    end

    def issue(scene, shot, type, severity, evidence)
      {
        unit_key: (shot || scene).key, scene_key: scene.key, shot_key: shot&.key,
        issue_type: type, severity: severity, evidence: evidence, source: "deterministic"
      }
    end
  end
end
