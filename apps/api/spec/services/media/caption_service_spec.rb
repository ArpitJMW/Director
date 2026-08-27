require "rails_helper"

RSpec.describe Media::CaptionService do
  it "groups words into timed cues from character alignment" do
    text = "the quick brown fox jumps over the lazy dog again"
    chars = text.chars
    step = 0.1
    alignment = {
      characters: chars,
      starts: chars.each_index.map { |i| (i * step).round(3) },
      ends: chars.each_index.map { |i| ((i + 1) * step).round(3) }
    }

    cues = described_class.build(text: text, alignment: alignment)

    expect(cues.length).to be >= 2
    expect(cues.map { |c| c[:text] }.join(" ").split.length).to eq(text.split.length)
    expect(cues.first[:start]).to eq(0.0)
    cues.each_cons(2) { |a, b| expect(b[:start]).to be >= a[:start] }
    cues.each { |c| expect(c[:text].split.length).to be <= described_class::MAX_WORDS_PER_CUE }
  end

  it "falls back to a single untimed cue when alignment is missing" do
    cues = described_class.build(text: "no timing here", alignment: {})
    expect(cues).to eq([ { text: "no timing here", start: 0.0, end: 0.0 } ])
  end
end
