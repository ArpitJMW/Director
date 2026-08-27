module Providers
  module LLM
    # Deterministic stand-in used in tests and local development without an API
    # key. Returns well-formed JSON for whichever stage is asking (detected from
    # the system prompt), so the pipeline runs end-to-end offline.
    class FakeAdapter < Base
      def name = "fake"
      def default_model = "fake-1"

      def chat(system:, messages:, max_tokens: 4096, model: nil)
        prompt = messages.map { |m| m[:content] }.join("\n")
        topic = prompt[/Topic:\s*(.+)/, 1]&.strip || "the subject"

        text = system.to_s.include?("storyboard engine") ? storyboard_json(topic) : script_json(topic)

        Result.new(
          text: text,
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
          creative_notes: "Keep the tone curious, not lecturing. Vary the visual treatment per scene.",
          claims: []
        }.to_json
      end

      def storyboard_json(topic)
        {
          scenes: [
            {
              narration: "We open on the core question about #{topic}.",
              visual_type: "text_animation",
              visual_prompt: "Kinetic title treatment posing the central question about #{topic}",
              caption: "What is #{topic}?",
              duration_seconds: 6,
              animation: "text_reveal",
              transition: "fade",
              background_music_level: 0.18
            },
            {
              narration: "The common assumption breaks down when you look closer.",
              visual_type: "image",
              visual_prompt: "Detailed illustration revealing the hidden mechanism behind #{topic}, dramatic lighting",
              caption: "The assumption breaks down",
              duration_seconds: 8,
              animation: "ken_burns",
              transition: "slide",
              background_music_level: 0.15
            },
            {
              narration: "Here is what actually explains #{topic}, and why it matters.",
              visual_type: "animated_diagram",
              visual_prompt: "Clean animated diagram explaining how #{topic} works, labelled parts",
              caption: "How it actually works",
              duration_seconds: 9,
              animation: "scale",
              transition: "fade",
              background_music_level: 0.12
            }
          ]
        }.to_json
      end
    end
  end
end
