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

        text =
          if system.to_s.include?("policy analyst")
            { verdict: "pass", reason: "The script follows a specific, well-defined angle." }.to_json
          elsif system.to_s.include?("You are the shot planner")
            shot_plan_json(prompt)
          elsif system.to_s.include?("You are the scene planner") || system.to_s.include?("storyboard engine")
            scene_plan_json(topic)
          else
            script_json(topic)
          end

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

      def scene_plan_json(topic)
        subject = "the central subject of #{topic}"
        environment = "a setting that suits #{topic}, consistent lighting"
        {
          scenes: [
            {
              purpose: "establish the setting",
              narration: "We open on the core question about #{topic}.",
              caption: "What is #{topic}?",
              duration_seconds: 6,
              content_type: "photorealistic",
              visual_type: "text_animation",
              asset_strategy: "text",
              subject: subject,
              environment: environment,
              action: "a slow reveal of the scene",
              camera: { shot_type: "establishing", movement: "slow_push_in", framing: "wide" },
              mood: "curious",
              visual_prompt: "#{subject}, wide establishing view, #{environment}, soft morning light",
              negative_prompt: "text, watermark, people, deformed",
              animation: "text_reveal",
              transition: "fade",
              background_music_level: 0.18
            },
            {
              purpose: "the turn",
              narration: "The common assumption breaks down when you look closer.",
              caption: "The assumption breaks down",
              duration_seconds: 10,
              content_type: "photorealistic",
              visual_type: "image",
              asset_strategy: "image",
              subject: subject,
              environment: environment,
              action: "a closer look reveals the hidden detail",
              camera: { shot_type: "medium", movement: "pan_left", framing: "medium" },
              mood: "tense",
              visual_prompt: "#{subject}, medium shot, #{environment}, dramatic side light",
              negative_prompt: "text, watermark, people, deformed, extra limbs",
              animation: "ken_burns",
              transition: "cut",
              background_music_level: 0.15
            },
            {
              purpose: "the payoff",
              narration: "Here is what actually explains #{topic}, and why it matters.",
              caption: "How it actually works",
              duration_seconds: 9,
              content_type: "documentary",
              visual_type: "image",
              asset_strategy: "image",
              subject: subject,
              environment: environment,
              action: "the full picture is shown",
              camera: { shot_type: "wide", movement: "slow_pull_out", framing: "wide" },
              mood: "resolved",
              visual_prompt: "#{subject}, wide shot, #{environment}, warm golden-hour light",
              negative_prompt: "text, watermark, people, deformed",
              animation: "scale",
              transition: "fade",
              background_music_level: 0.12
            }
          ]
        }.to_json
      end

      def shot_plan_json(prompt)
        keys = prompt.scan(/---\s*(scene_\d{2,})/).flatten.uniq
        keys = %w[scene_01] if keys.empty?
        {
          scenes: keys.map do |key|
            {
              key: key,
              shots: [
                {
                  duration_seconds: 4, shot_type: "establishing",
                  camera_movement: "slow_push_in", framing: "wide",
                  action: "the whole scene in frame",
                  visual_prompt: "wide establishing framing, consistent subject and environment",
                  negative_prompt: "text, watermark, people, deformed"
                },
                {
                  duration_seconds: 4, shot_type: "close_up",
                  camera_movement: "pan_right", framing: "close",
                  action: "a detail of the same moment",
                  visual_prompt: "close framing of the same subject and environment, same light",
                  negative_prompt: "text, watermark, people, deformed"
                }
              ]
            }
          end
        }.to_json
      end
    end
  end
end
