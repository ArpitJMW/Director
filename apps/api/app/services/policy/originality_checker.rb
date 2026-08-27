module Policy
  # spec §6: identify generic or overly derivative scripts/storylines. Uses the
  # LLM as a policy analyst; falls back to "review" if the model output is
  # unusable.
  module OriginalityChecker
    module_function

    def call(project:, provider: Providers.llm)
      script = project.current_script
      return CheckResult.review("No script to assess.") if script.nil?

      result = AiGeneration.track!(
        project: project, kind: "preflight", provider: provider.name,
        model: provider.default_model, request: { check: "originality" }
      ) do
        provider.chat(system: system_prompt, messages: [ { role: "user", content: user_prompt(script) } ], max_tokens: 600)
      end

      parse(result.text)
    rescue => e
      CheckResult.review("Originality check could not complete: #{e.message}")
    end

    def system_prompt
      <<~PROMPT
        You are a YouTube policy analyst. Judge whether a video script is original and
        substantive, or generic/derivative/mass-produced in the way YouTube's inauthentic
        content guidance describes (templated storyline, low-value listicle, thin
        rehash).

        Respond with ONLY JSON: { "verdict": "pass" | "warn", "reason": "one sentence" }
        Use "warn" only when the script genuinely reads as generic or derivative.
      PROMPT
    end

    def user_prompt(script)
      <<~TEXT
        Title: #{script.selected_title}
        Angle: #{script.story_angle}
        Hook: #{script.hook}
        Narration:
        #{script.full_narration}
      TEXT
    end
    private_class_method :system_prompt, :user_prompt

    def parse(text)
      json = text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      data = JSON.parse(json)
      verdict = data["verdict"] == "warn" ? "warn" : "pass"
      reason = data["reason"].to_s

      verdict == "warn" ? CheckResult.warn(reason.presence || "Script reads as generic.") : CheckResult.pass(reason.presence || "Script has a distinct angle.")
    rescue JSON::ParserError
      CheckResult.review("Originality model output was not valid JSON.")
    end
    private_class_method :parse
  end
end
