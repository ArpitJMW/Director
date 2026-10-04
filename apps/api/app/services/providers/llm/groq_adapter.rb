require "net/http"

module Providers
  module LLM
    # Groq — OpenAI-compatible chat completions on their LPU hardware. Genuinely
    # free developer tier (rate-limited, no per-token charge). Spec §15.
    class GroqAdapter < Base
      ENDPOINT = URI("https://api.groq.com/openai/v1/chat/completions").freeze
      DEFAULT_MODEL = ENV.fetch("LLM_MODEL", "openai/gpt-oss-120b")

      def initialize(api_key: ENV["GROQ_API_KEY"], model: DEFAULT_MODEL)
        super()
        raise Error, "GROQ_API_KEY not set" if api_key.blank?

        @api_key = api_key
        @model = model
      end

      def name = "groq"
      def default_model = @model

      private

      def fit_output(prompt_tokens, max_tokens, label)
        available = TPM_LIMIT - TOKEN_HEADROOM - prompt_tokens
        return max_tokens if max_tokens <= available

        if available >= MIN_OUTPUT_TOKENS
          Rails.logger.warn("[groq] #{label}: output cap #{max_tokens} shrunk to #{available} to fit the #{TPM_LIMIT} TPM limit (prompt ~#{prompt_tokens} tokens)")
          return available
        end

        raise Error, "groq request too large for #{label}: prompt ~#{prompt_tokens} tokens leaves #{available} " \
                     "for output under the #{TPM_LIMIT} TPM limit (need #{MIN_OUTPUT_TOKENS}); shorten the prompt or split the call"
      end

      public

      # Task 7.1: every Groq request must fit the per-request token limit (prompt
      # tokens plus the output cap). Oversized output caps are shrunk to fit; a
      # request that cannot fit at all raises a named error instead of a raw 413.
      TPM_LIMIT = ENV.fetch("GROQ_TPM_LIMIT", "8000").to_i
      TOKEN_HEADROOM = 200
      MIN_OUTPUT_TOKENS = 1500
      # Conservative: English prose is ~4 characters a token, JSON and lists are denser.
      CHARS_PER_TOKEN = 3.5

      def self.estimate_tokens(text) = (text.to_s.length / CHARS_PER_TOKEN).ceil

      def chat(system:, messages:, max_tokens: 4096, model: nil, label: nil, reasoning_effort: nil)
        used_model = model || @model
        label ||= "unnamed prompt (#{system.to_s.lines.first.to_s.strip.truncate(60)})"
        prompt_tokens = self.class.estimate_tokens(system) +
                        messages.sum { |m| self.class.estimate_tokens(m[:content]) } + 20
        max_tokens = fit_output(prompt_tokens, max_tokens, label)
        payload = {
          model: used_model,
          messages: [ { role: "system", content: system } ] +
                    messages.map { |m| { role: m[:role].to_s, content: m[:content] } },
          max_tokens: max_tokens,
          temperature: 0.9,
          # Our prompts all instruct "respond with only JSON" (required for this mode).
          response_format: { type: "json_object" }
        }
        # Task 7.2: gpt-oss reasoning tokens count against max_tokens. A lower
        # effort leaves more of the cap for the JSON the caller needs.
        payload[:reasoning_effort] = reasoning_effort if reasoning_effort

        body = post_json(payload)
        choice = body.dig("choices", 0) or raise Error, "groq returned no choices: #{body.inspect[0, 300]}"
        usage = body["usage"] || {}

        Result.new(
          text: choice.dig("message", "content").to_s.strip,
          model: used_model,
          provider: name,
          stop_reason: choice["finish_reason"],
          usage: {
            input_tokens: usage["prompt_tokens"].to_i,
            output_tokens: usage["completion_tokens"].to_i
          },
          provider_request_id: body["id"],
          raw: body
        )
      end

      private

      # Free tier is 8000 tokens/minute — the multi-stage planning pipeline
      # bursts past that, so honour a 429's stated cool-off and retry a few times.
      MAX_RETRIES = 4
      # Task 7.3 Part B: one retry sleep is capped at 60s. A longer wait means the
      # quota is spent for now, so the call fails with the reset time instead of
      # blocking a worker for minutes.
      MAX_WAIT = 60 # seconds — never sleep longer than this on one attempt

      def post_json(payload)
        attempt = 0
        begin
          attempt += 1
          res = do_post(payload)
          return JSON.parse(res.body) if res.code.to_i.between?(200, 299)

          if res.code.to_i == 429 && attempt <= MAX_RETRIES
            wait = retry_after(res)
            if wait > MAX_WAIT
              raise Error, "groq quota exhausted, resets at #{(Time.current + wait).strftime('%H:%M:%S %Z')} " \
                           "(retry in #{wait.round}s, longer than the #{MAX_WAIT}s cap)"
            end

            sleep(wait)
            raise Retry
          end
          raise Error, "groq HTTP #{res.code}: #{res.body.to_s[0, 500]}"
        rescue Retry
          retry
        end
      end

      Retry = Class.new(StandardError)

      def do_post(payload)
        http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(ENDPOINT)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = payload.to_json
        http.request(request)
      end

      def retry_after(res)
        header = res["retry-after"].to_f
        body_hint = res.body.to_s[/try again in ([\d.]+)s/, 1].to_f
        [ header, body_hint, 2.0 ].max + 1.0
      end
    end
  end
end
