module Ai
  # Task 6 Part C: one project-level setting (era, place, wardrobe, technology,
  # anachronisms to avoid). Stored in the existing projects.settings jsonb and
  # injected into every image prompt, so units share one world and QA can check
  # against it. One LLM call per project, skipped once a setting exists.
  class SettingService
    Error = Class.new(StandardError)
    FIELDS = %w[era place wardrobe technology avoid].freeze

    def initialize(project:, provider: Providers.llm)
      @project = project
      @provider = provider
    end

    def call
      return existing if existing

      prompt = Prompts.load("setting")
      result = AiGeneration.track!(
        project: @project, kind: "setting", provider: @provider.name, model: stage_model,
        request: { prompt_version: prompt.version }
      ) do |_gen|
        @provider.chat(system: prompt.text, messages: [ { role: "user", content: user_prompt }], max_tokens: 800, **stage_options)
      end

      setting = parse(result.text)
      @project.update!(settings: (@project.settings || {}).merge("setting" => setting))
      setting
    end

    private

    def existing
      @project.settings.is_a?(Hash) ? @project.settings["setting"].presence : nil
    end

    def user_prompt
      script = @project.current_script&.full_narration.to_s
      "Topic: #{@project.topic}\n\nScript:\n#{script.truncate(4000)}"
    end

    def parse(text)
      json = text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      data = JSON.parse(json)
      raise Error, "setting JSON is not an object" unless data.is_a?(Hash)

      FIELDS.to_h do |field|
        value = data[field]
        [ field, field == "avoid" ? Array(value).map(&:to_s).reject(&:blank?).first(5) : value.to_s.strip.truncate(200) ]
      end
    rescue JSON::ParserError => e
      raise Error, "setting JSON did not parse: #{e.message}"
    end
  end

  # Per-stage model (Task 7.3): this stage runs on a lighter Groq model unless
    # SETTING_MODEL says otherwise; other providers keep their own default.
  def stage_model = @provider.name == "groq" ? ENV.fetch("SETTING_MODEL", "openai/gpt-oss-20b") : @provider.default_model

  def stage_options = @provider.name == "groq" ? { model: stage_model } : {}
end
