module Media
  # Turns TTS character alignment into timed caption cues (spec §26). Groups
  # words into short lines suitable for on-screen display.
  module CaptionService
    module_function

    MAX_WORDS_PER_CUE = 7
    MAX_SECONDS_PER_CUE = 2.6

    # @param text [String] the narration
    # @param alignment [Hash] either character-level
    #   ({ characters:, starts:, ends: }, ElevenLabs) or word-level
    #   ({ words: [{ text:, start:, end: }] }, edge-tts)
    # @return [Array<Hash{text:,start:,end:}>]
    def build(text:, alignment:)
      normalized = alignment.symbolize_keys
      words =
        if normalized[:words].present?
          normalized[:words].map(&:symbolize_keys)
        else
          word_spans(normalized)
        end
      return fallback(text) if words.empty?

      cues = []
      current = []
      words.each do |word|
        current << word
        span = current.last[:end] - current.first[:start]
        if current.length >= MAX_WORDS_PER_CUE || span >= MAX_SECONDS_PER_CUE
          cues << cue(current)
          current = []
        end
      end
      cues << cue(current) if current.any?
      cues
    end

    def self.word_spans(alignment)
      chars = Array(alignment[:characters])
      starts = Array(alignment[:starts])
      ends = Array(alignment[:ends])
      return [] if chars.empty? || starts.length != chars.length

      spans = []
      buffer = ""
      buffer_start = nil

      chars.each_with_index do |char, i|
        if char.strip.empty?
          spans << { text: buffer, start: buffer_start, end: ends[i - 1] || starts[i] } if buffer.present?
          buffer = ""
          buffer_start = nil
        else
          buffer_start ||= starts[i]
          buffer << char
        end
      end
      spans << { text: buffer, start: buffer_start, end: ends.last } if buffer.present?
      spans
    end
    private_class_method :word_spans

    def self.cue(words)
      {
        text: words.map { |w| w[:text] }.join(" "),
        start: words.first[:start].to_f.round(3),
        end: words.last[:end].to_f.round(3)
      }
    end
    private_class_method :cue

    def self.fallback(text)
      [ { text: text.to_s.strip, start: 0.0, end: 0.0 } ]
    end
    private_class_method :fallback
  end
end
