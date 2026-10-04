module Ai
  # Task 6.2 Part 2: one project-level LOOK (visual style, palette, lighting,
  # lens language, texture, era, grade). Stored in the existing projects.settings
  # jsonb under "look", merged with the Task 6 setting, and editable later. One
  # Groq call per project; skipped once a look exists.
  class LookService
    Error = Class.new(StandardError)
    FIELDS = %w[visual_style colour_palette lighting lens texture era_setting grade avoid].freeze
    GRADES = %w[clean film].freeze

    def initialize(project:, provider: Providers.llm)
      @project = project
      @provider = provider
    end

    def call
      return existing if existing

      prompt = Prompts.load("look")
      result = AiGeneration.track!(
        project: @project, kind: "look", provider: @provider.name, model: stage_model,
        request: { prompt_version: prompt.version }
      ) do |_gen|
        @provider.chat(system: prompt.text, messages: [ { role: "user", content: user_prompt }], max_tokens: 800, **stage_options)
      end

      look = parse(result.text)
      @project.update!(settings: (@project.settings || {}).merge("look" => look))
      look
    end

    private

    def existing
      s = @project.settings
      s.is_a?(Hash) ? s["look"].presence : nil
    end

    def user_prompt
      script = @project.current_script&.full_narration.to_s
      setting = (@project.settings || {})["setting"]
      "Topic: #{@project.topic}\n\nScript:\n#{script.truncate(3000)}" \
        "#{"\n\nEstablished setting (keep consistent): #{setting.to_json}" if setting.is_a?(Hash)}"
    end

    def parse(text)
      json = text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      data = JSON.parse(json)
      raise Error, "look JSON is not an object" unless data.is_a?(Hash)

      look = FIELDS.to_h do |field|
        value = data[field]
        normalized = case field
                     when "colour_palette", "avoid" then Array(value).map { |v| v.to_s.strip.truncate(60) }.reject(&:blank?).first(5)
                     when "grade" then GRADES.include?(value.to_s) ? value.to_s : "clean"
                     else value.to_s.strip.truncate(240)
                     end
        [ field, normalized ]
      end
      look
    rescue JSON::ParserError => e
      raise Error, "look JSON did not parse: #{e.message.truncate(120)}"
    end
  end

  # Per-stage model (Task 7.3): this stage runs on a lighter Groq model unless
    # LOOK_MODEL says otherwise; other providers keep their own default.
  def stage_model = @provider.name == "groq" ? ENV.fetch("LOOK_MODEL", "openai/gpt-oss-20b") : @provider.default_model

  def stage_options = @provider.name == "groq" ? { model: stage_model } : {}
end
