require "rails_helper"

RSpec.describe Providers::Voice::GeminiTtsAdapter do
  let(:api_key) { "test-key" }
  let(:adapter) { described_class.new(api_key: api_key, model: "gemini-tts-test") }
  let(:url) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-tts-test:generateContent" }

  # Don't actually sleep through retry backoffs in tests.
  before { allow_any_instance_of(described_class).to receive(:sleep) }

  # Loud (well above SILENCE_RMS_THRESHOLD), constant-amplitude PCM — no real
  # silence anywhere, so Task 2.5's boundary-snap/trailing-trim logic finds
  # nothing quiet enough and leaves the proportional split untouched. This is
  # what every pre-Task-2.5 proportional-split assertion below relies on;
  # tests of the silence logic itself build their own PCM with real quiet
  # stretches (see #silent_frame / #loud_frame below).
  LOUD_SAMPLE = 12_000 # 16-bit signed, well over the 400 RMS threshold

  def gemini_body(duration_seconds, response_id: "resp_1")
    samples = (duration_seconds * described_class::SAMPLE_RATE).round
    pcm = loud_frame(samples)
    {
      responseId: response_id,
      candidates: [ { content: { parts: [ { inlineData: {
        mimeType: "audio/L16;rate=24000", data: Base64.strict_encode64(pcm)
      } } ] } } ]
    }.to_json
  end

  # `samples` samples alternating +LOUD_SAMPLE/-LOUD_SAMPLE (a square wave —
  # avoids a constant DC value some RMS-adjacent logic might special-case).
  def loud_frame(samples)
    (0...samples).map { |i| i.even? ? LOUD_SAMPLE : -LOUD_SAMPLE }.pack("s<*")
  end

  def silent_frame(samples)
    ([ 0 ] * samples).pack("s<*")
  end

  describe "#synthesize (per-scene path unchanged)" do
    it "returns a Result with word alignment covering the text" do
      stub_request(:post, url).to_return(status: 200, body: gemini_body(4.0), headers: { "Content-Type" => "application/json" })

      result = adapter.synthesize(text: "one two three four")

      expect(result.content_type).to eq("audio/wav")
      expect(result.duration_seconds).to be_within(0.05).of(4.0)
      expect(result.alignment[:words].map { |w| w[:text] }).to eq(%w[one two three four])
      expect(result.alignment[:words].last[:end]).to be_within(0.05).of(4.0)
    end
  end

  describe "#supports_batch?" do
    it "is true" do
      expect(adapter.supports_batch?).to be(true)
    end
  end

  describe "#synthesize_batch" do
    it "makes ONE call for texts that fit in one chunk and splits proportionally by word count, durations summing exactly to the total" do
      texts = [ "one two", "one two three four five six seven eight" ] # 2 words, 8 words -> 10 total
      stub_request(:post, url).to_return(status: 200, body: gemini_body(10.0))

      results = adapter.synthesize_batch(texts: texts)

      expect(a_request(:post, url)).to have_been_made.once
      expect(results.size).to eq(2)
      expect(results.sum(&:duration_seconds)).to be_within(0.001).of(10.0)
      expect(results[0].duration_seconds).to be_within(0.05).of(2.0)  # 2/10 of 10s
      expect(results[1].duration_seconds).to be_within(0.05).of(8.0)  # 8/10 of 10s
    end

    it "gives each result its own locally-rebased word alignment (starts at 0)" do
      texts = [ "alpha beta", "gamma delta epsilon" ]
      stub_request(:post, url).to_return(status: 200, body: gemini_body(5.0))

      results = adapter.synthesize_batch(texts: texts)

      expect(results[0].alignment[:words].map { |w| w[:text] }).to eq(%w[alpha beta])
      expect(results[0].alignment[:words].first[:start]).to eq(0.0)
      expect(results[1].alignment[:words].map { |w| w[:text] }).to eq(%w[gamma delta epsilon])
      expect(results[1].alignment[:words].first[:start]).to eq(0.0)
    end

    it "chunks into the fewest calls that fit MAX_CHARS_PER_CALL, in order" do
      long_a = "word " * ((described_class::MAX_CHARS_PER_CALL / 5) + 50) # forces a second chunk
      texts = [ long_a, "short scene two" ]
      stub_request(:post, url).to_return(status: 200, body: gemini_body(30.0)).then
        .to_return(status: 200, body: gemini_body(2.0))

      results = adapter.synthesize_batch(texts: texts)

      expect(a_request(:post, url)).to have_been_made.times(2)
      expect(results.size).to eq(2)
      expect(results[0].duration_seconds).to be_within(0.05).of(30.0) # alone in its own chunk
      expect(results[1].duration_seconds).to be_within(0.05).of(2.0)
    end

    it "returns nil for a chunk that fails after exhausting retries, without discarding an earlier chunk's results" do
      long_a = "word " * ((described_class::MAX_CHARS_PER_CALL / 5) + 50)
      texts = [ "short scene one", long_a ]
      # first call (short scene one, its own chunk) succeeds; second chunk 429s forever
      stub_request(:post, url).to_return(status: 200, body: gemini_body(2.0)).then
        .to_return(status: 429, body: { error: { message: "quota" } }.to_json)

      results = adapter.synthesize_batch(texts: texts)

      expect(results[0]).to be_present
      expect(results[0].duration_seconds).to be_within(0.05).of(2.0)
      expect(results[1]).to be_nil
    end

    describe "dead-air fix (Task 2.5)" do
      # 4.0s loud, 1.0s real silence, 5.0s loud = 10.0s total. 11 words then 9
      # words (20 total) -> raw proportional estimate for the boundary is
      # 11/20 * 10.0 = 5.5s, which falls INSIDE the second loud region, past
      # the true silence at [4.0, 5.0).
      let(:mixed_pcm) do
        loud_frame((4.0 * described_class::SAMPLE_RATE).round) +
          silent_frame((1.0 * described_class::SAMPLE_RATE).round) +
          loud_frame((5.0 * described_class::SAMPLE_RATE).round)
      end
      let(:mixed_body) do
        {
          responseId: "r", candidates: [ { content: { parts: [ { inlineData: {
            mimeType: "audio/L16;rate=24000", data: Base64.strict_encode64(mixed_pcm)
          } } ] } } ]
        }.to_json
      end
      let(:eleven_and_nine_words) { [ (["word"] * 11).join(" "), (["word"] * 9).join(" ") ] }

      it "snaps the boundary toward the real silence instead of the raw estimate deep in loud speech" do
        stub_request(:post, url).to_return(status: 200, body: mixed_body)

        results = adapter.synthesize_batch(texts: eleven_and_nine_words)

        # The un-snapped estimate (5.5s) sits 0.5s into the SECOND loud region,
        # after the real silence entirely. A boundary that respects the
        # silence lands meaningfully earlier than that.
        expect(results[0].duration_seconds).to be < 5.3
      end

      it "trims the resulting trailing silence rather than playing it out as dead air" do
        stub_request(:post, url).to_return(status: 200, body: mixed_body)

        results = adapter.synthesize_batch(texts: eleven_and_nine_words)

        # scene 1 is 4.0s of real speech; it must not carry the full ~1s pause
        # as untrimmed trailing silence.
        expect(results[0].duration_seconds).to be < 4.0 + described_class::MAX_TRAILING_SILENCE
        expect(results[0].duration_seconds).to be > 4.0 # some natural buffer is kept, not zero
      end

      it "leaves scene 2 starting essentially where real speech resumes (no big leading gap)" do
        stub_request(:post, url).to_return(status: 200, body: mixed_body)

        results = adapter.synthesize_batch(texts: eleven_and_nine_words)

        expect(results[1].duration_seconds).to be_within(0.2).of(5.0)
      end

      it "keeps snapped boundaries ordered with a minimum segment length (Task 5C)" do
        # 3.0s loud, 1.0s silence, 3.0s loud. Two internal boundaries (a short
        # scene's start and end) both sit inside the silence; independent
        # snapping would drop them onto the same quiet sample.
        rate = described_class::SAMPLE_RATE
        pcm = loud_frame((3.0 * rate).round) + silent_frame((1.0 * rate).round) + loud_frame((3.0 * rate).round)
        boundaries = [ 0, (3.3 * rate).round, (3.4 * rate).round, pcm.bytesize / 2 ]

        snapped = adapter.send(:snap_internal_boundaries, pcm, boundaries)

        min_gap = (described_class::MIN_SEGMENT_SECONDS * rate).round
        expect(snapped[2] - snapped[1]).to be >= min_gap
        expect(snapped.each_cons(2).all? { |a, b| b > a }).to be true
        expect(snapped.first).to eq(0)
        expect(snapped.last).to eq(pcm.bytesize / 2)
      end

      it "falls back to the untouched proportional estimate when nothing in the window is quiet enough" do
        stub_request(:post, url).to_return(status: 200, body: gemini_body(10.0)) # loud throughout, no silence anywhere

        results = adapter.synthesize_batch(texts: [ "one two", "one two three four five six seven eight" ])

        expect(results[0].duration_seconds).to be_within(0.05).of(2.0) # 2/10 words
        expect(results[1].duration_seconds).to be_within(0.05).of(8.0)
      end
    end

    describe "leading-silence trim (Task 2.7)" do
      # Same 4.0s loud / 1.0s silent / 5.0s loud audio as the dead-air
      # fixture above, but word counts (4 then 6, out of 10) chosen so the
      # raw proportional estimate lands at exactly 4.0s -- the START of the
      # silent block -- instead of past it. The snap then favors the quiet
      # point closest to THAT estimate, i.e. the LEFT edge of the silence, so
      # almost the whole 1.0s pause ends up as scene 2's LEADING silence
      # rather than scene 1's trailing silence -- the case Task 2.5's own
      # trailing-only trim couldn't reach.
      let(:mixed_pcm) do
        loud_frame((4.0 * described_class::SAMPLE_RATE).round) +
          silent_frame((1.0 * described_class::SAMPLE_RATE).round) +
          loud_frame((5.0 * described_class::SAMPLE_RATE).round)
      end
      let(:mixed_body) do
        {
          responseId: "r", candidates: [ { content: { parts: [ { inlineData: {
            mimeType: "audio/L16;rate=24000", data: Base64.strict_encode64(mixed_pcm)
          } } ] } } ]
        }.to_json
      end
      let(:four_and_six_words) { [ (["word"] * 4).join(" "), (["word"] * 6).join(" ") ] }

      it "trims scene 2's leading silence down near KEEP_LEADING_SILENCE" do
        stub_request(:post, url).to_return(status: 200, body: mixed_body)

        results = adapter.synthesize_batch(texts: four_and_six_words)

        # Untrimmed, scene 2 would carry the whole ~1.0s pause plus its 5.0s
        # of real speech (~6.0s of duration).
        expect(results[1].duration_seconds).to be < 5.0 + described_class::MAX_LEADING_SILENCE
      end

      it "never trims into real speech — scene 2's audio still contains all 5.0s of it" do
        stub_request(:post, url).to_return(status: 200, body: mixed_body)

        results = adapter.synthesize_batch(texts: four_and_six_words)

        expect(results[1].duration_seconds).to be >= 5.0
      end

      it "keeps the combined transition gap (scene 1's trailing + scene 2's leading silence) small" do
        stub_request(:post, url).to_return(status: 200, body: mixed_body)

        results = adapter.synthesize_batch(texts: four_and_six_words)

        total_silence = (results[0].duration_seconds - 4.0) + (results[1].duration_seconds - 5.0)
        expect(total_silence).to be < 0.5
      end

      it "leaves scene 1 alone when it has no meaningful trailing silence of its own" do
        stub_request(:post, url).to_return(status: 200, body: mixed_body)

        results = adapter.synthesize_batch(texts: four_and_six_words)

        expect(results[0].duration_seconds).to be_within(0.05).of(4.0)
      end
    end

    it "raises only when every chunk fails" do
      stub_request(:post, url).to_return(status: 429, body: { error: { message: "quota" } }.to_json)

      expect { adapter.synthesize_batch(texts: [ "one text" ]) }.to raise_error(described_class::Error, /chunk\(s\) failed/)
    end
  end

  describe "retry behaviour (reuses Providers::LLM::GroqAdapter's pattern)" do
    it "retries on 429 honouring Retry-After, then succeeds" do
      stub_request(:post, url)
        .to_return(status: 429, headers: { "Retry-After" => "1" }, body: { error: { message: "quota" } }.to_json).then
        .to_return(status: 200, body: gemini_body(1.0))

      result = adapter.synthesize(text: "hi")

      expect(result).to be_present
      expect(a_request(:post, url)).to have_been_made.times(2)
    end

    it "retries a transient connection error (SSL/TLS), then succeeds" do
      stub_request(:post, url)
        .to_raise(OpenSSL::SSL::SSLError.new("SSL_read: (null) (tls_retry_write_records failure)")).then
        .to_return(status: 200, body: gemini_body(1.0))

      result = adapter.synthesize(text: "hi")

      expect(result).to be_present
      expect(a_request(:post, url)).to have_been_made.times(2)
    end

    it "gives up after a bounded number of attempts" do
      stub_request(:post, url).to_return(status: 429, body: { error: { message: "quota" } }.to_json)

      expect { adapter.synthesize(text: "hi") }.to raise_error(described_class::Error)
      expect(a_request(:post, url)).to have_been_made.times(described_class::MAX_RETRIES + 1)
    end
  end

  describe "error body storage" do
    it "no longer truncates at 400 characters" do
      long_message = "x" * 1500
      stub_request(:post, url).to_return(status: 500, body: { error: { message: long_message } }.to_json)

      expect { adapter.synthesize(text: "hi") }.to raise_error(described_class::Error) do |e|
        expect(e.message).to include(long_message)
      end
    end
  end
end
