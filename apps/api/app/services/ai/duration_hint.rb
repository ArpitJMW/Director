module Ai
  # Pulls an explicit target length out of free-text the user wrote in the topic
  # or creator instructions ("a 30-40 second video", "~45s", "two minutes").
  # Returns seconds (Integer) or nil. For a range, takes the midpoint.
  module DurationHint
    module_function

    RANGE = /(\d+)\s*(?:-|–|to)\s*(\d+)\s*(seconds?|secs?|s|minutes?|mins?|m)\b/i
    SINGLE = /(?:~|about|around|approx\.?\s*)?(\d+(?:\.\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|m)\b/i

    def parse(*texts)
      text = texts.compact.join("\n")
      return nil if text.blank?

      if (m = text.match(RANGE))
        lo, hi = m[1].to_f, m[2].to_f
        return to_seconds((lo + hi) / 2.0, m[3])
      end
      if (m = text.match(SINGLE))
        return to_seconds(m[1].to_f, m[2])
      end
      nil
    end

    def to_seconds(value, unit)
      secs = unit.downcase.start_with?("m") ? value * 60 : value
      secs = secs.round
      return nil unless secs.between?(5, 3600)

      secs
    end
  end
end
