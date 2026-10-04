module Media
  # Reconciles a narrated scene's screen time to the REAL measured audio
  # duration once TTS has actually run (Phase 1 Task 2.6). The scene planner
  # sets duration_seconds off a pre-TTS word-count/pace estimate; that
  # estimate is often wrong — a real narration that runs long gets clipped at
  # the Sequence boundary (Remotion scopes <Audio> to its enclosing
  # <Sequence>), and one that runs short leaves dead air. Called from both
  # the batch and single-scene voice paths right after a scene's audio is
  # stored, so it applies identically no matter which path ran.
  #
  # Non-narrated scenes are simply never passed here, so their planned
  # duration is untouched.
  module SceneDurationService
    module_function

    # Phase 1 Task 2.7: this used to be 0.4s, added on top of whatever
    # trailing silence Providers::Voice::GeminiTtsAdapter's own trim already
    # left in the stored clip (previously up to ~0.5s, since its old trim
    # only engaged past a 0.6s natural pause) — the two compounded with the
    # next scene's own leading silence into ~1.1-1.2s of dead air at every
    # transition. GeminiTtsAdapter now trims both ends of every segment down
    # to a small, tightly-bounded residual (~0.15-0.2s), so this only needs to
    # add a small fixed visual buffer past the audio's own end, not cover for
    # an untrimmed tail — the total transition gap (this + the next scene's
    # own small leading residual) lands at ~0.35-0.5s instead.
    TAIL_PADDING = 0.15
    MIN_DURATION = 2.5

    # @param scene [Scene]
    # @param measured_duration [Numeric] the real synthesized audio length,
    #   in seconds
    # @return [Scene]
    def reconcile!(scene:, measured_duration:)
      new_duration = [ measured_duration.to_f + TAIL_PADDING, MIN_DURATION ].max.round(2)
      old_duration = scene.duration_seconds.to_f
      return scene if (new_duration - old_duration).abs < 0.01

      scene.update!(duration_seconds: new_duration)
      rescale_shots!(scene, old_duration, new_duration)
      scene
    end

    def self.rescale_shots!(scene, old_duration, new_duration)
      shots = scene.shots.to_a
      return if shots.empty?

      ratio = new_duration / old_duration
      scaled = shots.map { |shot| [ (shot.duration_seconds.to_f * ratio).round(2), 0.1 ].max }

      # Independently-rounded proportional scaling can leave the sum a cent
      # off the scene's exact new duration — nudge the last shot to close it,
      # the same "last shot absorbs rounding drift" rule Ai::ShotPlanner uses.
      scaled[-1] = [ (new_duration - scaled[0...-1].sum).round(2), 0.1 ].max

      shots.zip(scaled).each { |shot, duration| shot.update!(duration_seconds: duration) }
    end
    private_class_method :rescale_shots!
  end
end
