module Media
  # Task 5C pacing: no visual unit holds longer than MAX_UNIT_SECONDS. A unit
  # over that limit is subdivided into sub-shots that REUSE the same image
  # with a different camera move — no new image generation. Durations still
  # sum exactly to the original (2-decimal arithmetic, last part absorbs
  # rounding). Pure: no database, no provider.
  module VisualPacing
    MAX_UNIT_SECONDS = 4.5

    # Sub-shots of one unit alternate between two punch-ins (Task 6 F): each one
    # tightens to ~1.25-1.4x on a different side of the frame, drifting the
    # opposite way. A slow pan of one still read as the same shot, so the parts
    # are made visibly different rather than just moved.
    CAMERA_CYCLE = %w[punch_in_left punch_in_right].freeze

    module_function

    # @param units [Array<Hash>] each { id:, duration:, camera_movement:, overlay:, ... }
    # @return [Array<Hash>] the same units, with any over-long unit replaced by parts
    def subdivide(units, max_seconds: MAX_UNIT_SECONDS, cycle_offset: 0)
      cycle = cycle_offset
      units.flat_map do |unit|
        total = unit[:duration].to_f.round(2)
        next [ unit.merge(duration: total) ] if total <= max_seconds

        durations = split_durations(total, max_seconds)
        durations.each_with_index.map do |part, i|
          camera = CAMERA_CYCLE[cycle % CAMERA_CYCLE.size]
          cycle += 1
          unit.merge(
            id: "#{unit[:id]}_p#{i + 1}",
            duration: part,
            camera_movement: camera,
            # An overlay belongs to the unit's first part only; repeating it
            # would re-enter the same name every few seconds.
            overlay: i.zero? ? unit[:overlay] : nil
          )
        end
      end
    end

    # Splits `total` into the fewest parts that each fit within `max`, as
    # equal as 2-decimal arithmetic allows, summing exactly to `total`.
    def split_durations(total, max)
      parts = (total / max).ceil
      base = (total / parts).floor(2)
      durations = Array.new(parts - 1) { base }
      durations << (total - durations.sum).round(2)
      durations
    end
  end
end
