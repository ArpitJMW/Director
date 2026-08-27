module Providers
  module LLM
    # Deterministic stand-in used in tests and local development without an API
    # key. Returns a well-formed script JSON payload so the pipeline can run
    # end-to-end offline.
    class FakeAdapter < Base
      def name = "fake"
      def default_model = "fake-1"

      def chat(system:, messages:, max_tokens: 4096, model: nil)
        prompt = messages.map { |m| m[:content] }.join("\n")
        topic = prompt[/Topic:\s*(.+)/, 1]&.strip || "the subject"

        Result.new(
          text: script_json(topic),
          model: model || default_model,
          provider: name,
          stop_reason: "end_turn",
          usage: { input_tokens: prompt.size / 4, output_tokens: 320 },
          provider_request_id: "fake_#{SecureRandom.hex(6)}",
          raw: nil
        )
      end

      private

      def script_json(topic)
        {
          title_options: [
            "The Untold Story of #{topic.capitalize}",
            "#{topic.capitalize}, Explained",
            "What Everyone Gets Wrong About #{topic.capitalize}"
          ],
          selected_title: "#{topic.capitalize}, Explained",
          hook: "Most people have no idea how #{topic} actually works — here's the real story.",
          story_angle: "A concise, myth-busting explainer that follows one concrete thread through #{topic}.",
          sections: [
            { heading: "Setup", narration: "We open on the core question about #{topic}." },
            { heading: "Turn", narration: "The common assumption breaks down when you look closer." },
            { heading: "Payoff", narration: "Here is what actually explains #{topic}, and why it matters." }
          ],
          full_narration: "We open on the core question about #{topic}. " \
                          "The common assumption breaks down when you look closer. " \
                          "Here is what actually explains #{topic}, and why it matters.",
          estimated_duration_seconds: 95,
          creative_notes: "Keep the tone curious, not lecturing. Vary the visual treatment per section.",
          claims: []
        }.to_json
      end
    end
  end
end
