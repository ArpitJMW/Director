require "net/http"

module Providers
  module Voice
    # Google Gemini text-to-speech (spec §15, §26). Works on the Gemini API key
    # even when image generation is quota-limited. Returns raw PCM which we wrap
    # in a WAV container. Gemini TTS gives no word timing, so captions use an
    # even distribution across the clip.
    #
    # Phase 1 Task 2.4: the free tier returns HTTP 429 after ~1-2 calls
    # ("generate_content_free_tier_requests, limit: 3"), and a per-scene design
    # burns one call per scene — so #supports_batch? is true and
    # #synthesize_batch joins many scenes' narration into the fewest possible
    # calls, then slices the single returned clip back into per-scene audio by
    # proportional word count — the same even-distribution assumption
    # #synthesize already uses for captions, just applied at scene boundaries
    # too. post_json also now retries transient connection failures (observed
    # in real runs: intermittent SSL_read/TLS errors), not just 429s.
    class GeminiTtsAdapter < Base
      HOST = "https://generativelanguage.googleapis.com/v1beta/models".freeze
      DEFAULT_MODEL = ENV.fetch("GEMINI_TTS_MODEL", "gemini-2.5-flash-preview-tts")
      DEFAULT_VOICE = ENV.fetch("GEMINI_TTS_VOICE", "Charon")
      SAMPLE_RATE = 24_000 # Gemini TTS: L16 PCM @ 24 kHz mono

      # No documented hard input limit for this model at time of writing;
      # chunk conservatively so one call's text (and its audio) stays a
      # reasonable size rather than assuming an unverified maximum.
      MAX_CHARS_PER_CALL = 4000

      def initialize(api_key: ENV["GEMINI_API_KEY"], model: DEFAULT_MODEL)
        super()
        raise Error, "GEMINI_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @model = model
      end

      def name = "gemini_tts"
      def default_model = @model
      def default_voice_id = DEFAULT_VOICE
      def supports_batch? = true

      def synthesize(text:, voice_id: nil, model: nil)
        used_model = model || @model
        voice = voice_id.presence || DEFAULT_VOICE

        pcm, response = raw_audio(text: text, voice: voice, model: used_model)
        duration = pcm.bytesize / (2.0 * SAMPLE_RATE)

        Result.new(
          audio_bytes: wav(pcm),
          content_type: "audio/wav",
          alignment: { words: even_words(text, duration) },
          duration_seconds: duration.round(3),
          model: used_model,
          provider: name,
          provider_request_id: response["responseId"],
          cost_usd: usage_cost(response, used_model),
          raw: { estimated_cost_usd: usage_list_cost(response, used_model) }
        )
      end

      # @param texts [Array<String>] narration, one per scene, in order
      # @return [Array<Result, nil>] one per input text, same order. An entry
      #   is nil when its chunk failed after exhausting retries — a later
      #   chunk's failure never discards an earlier chunk's already-decoded
      #   audio, so one bad chunk doesn't cost every scene in the batch.
      #   Raises only when EVERY chunk failed (nothing at all to return).
      def synthesize_batch(texts:, voice_id: nil, model: nil)
        used_model = model || @model
        voice = voice_id.presence || DEFAULT_VOICE

        results = Array.new(texts.size)
        chunk_errors = []
        chunk_texts(texts).each do |chunk|
          joined = chunk.map { |c| c[:text] }.join("\n\n")
          pcm, response = raw_audio(text: joined, voice: voice, model: used_model)
          slice_chunk(chunk, pcm, response, used_model).each { |i, result| results[i] = result }
        rescue Error => e
          chunk_errors << e.message
        end

        raise Error, "all chunk(s) failed: #{chunk_errors.join('; ')}" if results.compact.empty? && chunk_errors.any?

        results
      end

      private

      # Groups texts, in order, into as few chunks as fit MAX_CHARS_PER_CALL as
      # possible (a single text longer than the limit becomes its own chunk —
      # batching is about call COUNT, splitting one scene's narration further
      # isn't this method's job).
      def chunk_texts(texts)
        indexed = texts.each_with_index.map { |t, i| { index: i, text: t.to_s } }
        chunks = []
        current = []
        current_len = 0

        indexed.each do |item|
          len = item[:text].length
          added_len = (current.empty? ? 0 : 2) + len # "\n\n" joiner once inserted
          if current.any? && current_len + added_len > MAX_CHARS_PER_CALL
            chunks << current
            current = []
            current_len = 0
            added_len = len
          end
          current << item
          current_len += added_len
        end
        chunks << current if current.any?
        chunks
      end

      # Splits one chunk's combined PCM by each text's word count share of the
      # chunk's total words (#synthesize's own even-distribution assumption),
      # then (Phase 1 Task 2.5) snaps each INTERNAL boundary to the quietest
      # point within SILENCE_SEARCH_WINDOW of that estimate — real speech
      # rarely splits exactly on the word-count fraction, so cutting there
      # lands mid-word about as often as it lands in an actual pause. When no
      # sufficiently quiet point exists nearby (continuous speech), the
      # proportional estimate is kept as-is. The chunk's own start/end are
      # never moved. Each segment's own trailing silence (e.g. the pause
      # Gemini renders for the "\n\n" joiner) is then trimmed if it runs
      # longer than MAX_TRAILING_SILENCE, rather than playing out as dead air.
      def slice_chunk(chunk, pcm, response, used_model)
        total_samples = pcm.bytesize / 2
        word_counts = chunk.map { |c| [ c[:text].split.size, 1 ].max }
        total_words = word_counts.sum
        chunk_cost = usage_cost(response, used_model)
        chunk_list_cost = usage_list_cost(response, used_model)

        boundaries = proportional_boundaries(total_samples, word_counts, total_words)
        boundaries = snap_internal_boundaries(pcm, boundaries)

        chunk.each_with_index.map do |item, i|
          seg_pcm = pcm.byteslice(boundaries[i] * 2, (boundaries[i + 1] - boundaries[i]) * 2) || ""
          seg_pcm = trim_leading_silence(seg_pcm)
          seg_pcm = trim_trailing_silence(seg_pcm)

          duration = seg_pcm.bytesize / (2.0 * SAMPLE_RATE)
          result = Result.new(
            audio_bytes: wav(seg_pcm),
            content_type: "audio/wav",
            alignment: { words: even_words(item[:text], duration) },
            duration_seconds: duration.round(3),
            model: used_model,
            provider: name,
            provider_request_id: response["responseId"],
            cost_usd: chunk_cost * word_counts[i] / total_words.to_f,
            raw: { estimated_cost_usd: chunk_list_cost * word_counts[i] / total_words.to_f }
          )
          [ item[:index], result ]
        end
      end

      # @return [Array<Integer>] N+1 sample offsets (0, ..., total_samples) for
      #   N texts — boundaries[i]..boundaries[i+1] is text i's proportional
      #   share. The last share absorbs rounding drift so every sample is
      #   accounted for.
      def proportional_boundaries(total_samples, word_counts, total_words)
        boundaries = [ 0 ]
        cumulative = 0
        word_counts[0...-1].each do |words|
          cumulative += words
          boundaries << (total_samples * cumulative / total_words.to_f).round
        end
        boundaries << total_samples
      end

      SILENCE_SEARCH_WINDOW = 1.5 # seconds either side of the estimate (per spec)
      MIN_SEGMENT_SECONDS = 0.8 # Task 5C: never shrink a scene's audio below this by snapping
      SILENCE_WINDOW_SECONDS = 0.02 # 20ms analysis frames
      SILENCE_RMS_THRESHOLD = 400 # 16-bit PCM RMS below this reads as "quiet"

      # Moves each INTERNAL boundary (not index 0 or the last) to the quietest
      # point within SILENCE_SEARCH_WINDOW, if any point there is quiet enough;
      # otherwise leaves that boundary at its proportional estimate.
      # Task 5C: boundaries are snapped in order and each keeps at least
      # MIN_SEGMENT_SECONDS of audio on both sides. Snapping every boundary
      # independently let a short scene's start and end both land on the same
      # quiet gap, collapsing that scene to ~0.06s of audio (its narration was
      # silently dropped and the scene reconciled to its 2.5s floor).
      def snap_internal_boundaries(pcm, boundaries)
        total = pcm.bytesize / 2
        min_gap = (MIN_SEGMENT_SECONDS * SAMPLE_RATE).round
        snapped = boundaries.dup
        (1...(boundaries.size - 1)).each do |i|
          candidate = quietest_point_near(pcm, boundaries[i], total) || boundaries[i]
          lower = snapped[i - 1] + min_gap
          upper = [ boundaries[i + 1] - min_gap, lower ].max
          snapped[i] = candidate.clamp(lower, upper)
        end
        snapped
      end

      # Among the quietest frames in the window, prefers whichever is CLOSEST
      # to the original estimate (rather than always the first one scanned) —
      # the least disruptive move away from the model's own word-count guess,
      # and for a real pause (a shallow, roughly centered dip in energy rather
      # than a hard on/off cliff) this naturally lands near the middle of it.
      def quietest_point_near(pcm, estimate, total_samples)
        window = (SILENCE_SEARCH_WINDOW * SAMPLE_RATE).round
        step = (SILENCE_WINDOW_SECONDS * SAMPLE_RATE).round
        lo = [ estimate - window, 0 ].max
        hi = [ estimate + window, total_samples - step ].min
        return nil if hi < lo

        best_sample = nil
        best_rms = Float::INFINITY
        best_distance = Float::INFINITY
        lo.step(hi, step) do |s|
          frame = pcm.byteslice(s * 2, step * 2)
          next if frame.nil? || frame.bytesize < step * 2

          rms = frame_rms(frame)
          distance = (s - estimate).abs
          if rms < best_rms || (rms == best_rms && distance < best_distance)
            best_rms = rms
            best_distance = distance
            best_sample = s
          end
        end

        best_sample if best_sample && best_rms <= SILENCE_RMS_THRESHOLD
      end

      # Phase 1 Task 2.7: both thresholds lowered from the Task 2.5 originals
      # (0.6 / 0.25). At 0.6, a segment's natural inter-sentence pause (often
      # ~0.3-0.55s) never crossed the trigger and was left untouched; that
      # untouched tail then compounded with Media::SceneDurationService's own
      # padding and the NEXT segment's leading silence into ~1.1-1.2s of dead
      # air at every scene transition (found in the Task 2.6 real check).
      # Trimming (nearly) every segment down to a small, consistent residual
      # closes that gap without needing to know each clip's exact natural
      # pause length ahead of time.
      MAX_TRAILING_SILENCE = 0.2 # seconds — trim a tail quieter than this for longer
      KEEP_TRAILING_SILENCE = 0.15 # seconds of natural buffer left after trimming
      MAX_LEADING_SILENCE = 0.15 # seconds — trim a lead-in quieter than this for longer
      KEEP_LEADING_SILENCE = 0.1 # seconds of natural buffer left after trimming

      # Walks backward from a segment's end in SILENCE_WINDOW_SECONDS frames;
      # if the trailing quiet run exceeds MAX_TRAILING_SILENCE, cuts it down to
      # KEEP_TRAILING_SILENCE rather than playing out as dead air.
      def trim_trailing_silence(seg_pcm)
        step = (SILENCE_WINDOW_SECONDS * SAMPLE_RATE).round
        total = seg_pcm.bytesize / 2
        return seg_pcm if total <= step

        quiet_samples = 0
        s = total - step
        while s >= 0
          frame = seg_pcm.byteslice(s * 2, step * 2)
          break if frame.nil? || frame.bytesize < step * 2
          break if frame_rms(frame) > SILENCE_RMS_THRESHOLD

          quiet_samples += step
          s -= step
        end

        return seg_pcm if quiet_samples / SAMPLE_RATE.to_f <= MAX_TRAILING_SILENCE

        keep_samples = (KEEP_TRAILING_SILENCE * SAMPLE_RATE).round
        cut_samples = quiet_samples - keep_samples
        return seg_pcm if cut_samples <= 0

        seg_pcm.byteslice(0, (total - cut_samples) * 2) || seg_pcm
      end

      # Mirrors #trim_trailing_silence at the front of a segment instead of
      # the back: walks forward from sample 0, and if the leading quiet run
      # exceeds MAX_LEADING_SILENCE, cuts it down to KEEP_LEADING_SILENCE.
      # Never removes a frame past the first one whose RMS reads as speech, so
      # this can only shorten silence, never real narration.
      def trim_leading_silence(seg_pcm)
        step = (SILENCE_WINDOW_SECONDS * SAMPLE_RATE).round
        total = seg_pcm.bytesize / 2
        return seg_pcm if total <= step

        quiet_samples = 0
        s = 0
        while s < total
          frame = seg_pcm.byteslice(s * 2, step * 2)
          break if frame.nil? || frame.bytesize < step * 2
          break if frame_rms(frame) > SILENCE_RMS_THRESHOLD

          quiet_samples += step
          s += step
        end

        return seg_pcm if quiet_samples / SAMPLE_RATE.to_f <= MAX_LEADING_SILENCE

        keep_samples = (KEEP_LEADING_SILENCE * SAMPLE_RATE).round
        cut_samples = quiet_samples - keep_samples
        return seg_pcm if cut_samples <= 0

        seg_pcm.byteslice(cut_samples * 2, (total - cut_samples) * 2) || seg_pcm
      end

      def frame_rms(frame)
        samples = frame.unpack("s<*")
        return 0.0 if samples.empty?

        Math.sqrt(samples.sum { |s| s.to_f * s } / samples.size)
      end

      # Real cost from the response's token usage (Task 5B) — the audio output
      # is what makes TTS expensive, and it's billed per output token.
      def usage_cost(response, model)
        usage = response["usageMetadata"]
        if usage.blank?
          Rails.logger.warn("[gemini_tts] no usageMetadata in response — cost recorded as $0")
          return 0.0
        end

        Providers::Pricing.cost_usd(
          provider: name, model: model,
          input_tokens: usage["promptTokenCount"].to_i,
          output_tokens: usage["candidatesTokenCount"].to_i
        )
      end

      # Task 6 F: list price for the same usage, kept beside the billed cost.
      def usage_list_cost(response, model)
        usage = response["usageMetadata"] || {}
        Providers::Pricing.list_cost_usd(
          provider: name, model: model,
          input_tokens: usage["promptTokenCount"].to_i,
          output_tokens: usage["candidatesTokenCount"].to_i
        )
      end

      def raw_audio(text:, voice:, model:)
        uri = URI("#{HOST}/#{model}:generateContent")
        body = {
          contents: [ { parts: [ { text: text } ] } ],
          generationConfig: {
            responseModalities: [ "AUDIO" ],
            speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } }
          }
        }

        response = post_json(uri, body)
        part = response.dig("candidates", 0, "content", "parts", 0)
        inline = part&.dig("inlineData") || part&.dig("inline_data")
        raise Error, "gemini-tts returned no audio (#{response.dig('candidates', 0, 'finishReason')})" if inline.nil?

        [ Base64.decode64(inline["data"]), response ]
      end

      # Bounded retry for both 429 (honouring Retry-After when given, same
      # pattern as Providers::LLM::GroqAdapter) and the transient connection
      # failures observed in real runs (SSL/TLS resets, timeouts) — those
      # aren't quota, they're the network dropping mid-request, and a retry
      # after a short pause routinely succeeds.
      MAX_RETRIES = 4
      MAX_WAIT = 65
      TRANSIENT_ERRORS = [
        OpenSSL::SSL::SSLError, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EPIPE,
        Net::OpenTimeout, Net::ReadTimeout, EOFError, SocketError
      ].freeze
      # Previously truncated to 400 chars, which cut Gemini's own error body
      # (including the quota metric/limit) off mid-sentence in stored
      # failure_reasons. Raised substantially rather than removed outright, so
      # a pathological non-JSON error body from an intermediary can't bloat a
      # text column unbounded.
      ERROR_BODY_LIMIT = 2000

      Retry = Class.new(StandardError)

      def post_json(uri, body)
        attempt = 0
        begin
          attempt += 1
          res = do_post(uri, body)
          return JSON.parse(res.body) if res.code.to_i.between?(200, 299)

          if res.code.to_i == 429 && attempt <= MAX_RETRIES
            sleep(retry_after(res))
            raise Retry
          end
          raise Error, "gemini-tts HTTP #{res.code}: #{res.body.to_s[0, ERROR_BODY_LIMIT]}"
        rescue Retry
          retry
        rescue *TRANSIENT_ERRORS => e
          if attempt <= MAX_RETRIES
            sleep([ 2 * attempt, MAX_WAIT ].min.to_f)
            retry
          end
          raise Error, "gemini-tts connection failed after #{attempt} attempt(s): #{e.class}: #{e.message}"
        end
      end

      def do_post(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 180

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-goog-api-key"] = @api_key
        request.body = body.to_json
        http.request(request)
      end

      def retry_after(res)
        header = res["retry-after"].to_f
        body_hint = res.body.to_s[/try again in ([\d.]+)s/, 1].to_f
        [ [ header, body_hint, 2.0 ].max + 1.0, MAX_WAIT ].min
      end

      def even_words(text, duration)
        tokens = text.to_s.split
        return [] if tokens.empty?

        step = duration / tokens.length
        tokens.each_with_index.map do |word, i|
          { text: word, start: (i * step).round(3), end: ((i + 1) * step).round(3) }
        end
      end

      def wav(pcm)
        data = pcm.bytesize
        header = [
          "RIFF", 36 + data, "WAVE",
          "fmt ", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16,
          "data", data
        ].pack("a4Va4a4VvvVVvva4V")
        header + pcm
      end
    end
  end
end
