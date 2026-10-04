module Providers
  # Raised when a paid provider/model is requested while ALLOW_PAID_PROVIDERS
  # is not "true" (Task 5B). Named loudly so a stage failure says exactly why.
  class PaidProviderBlocked < StandardError; end

  module_function

  # The configured LLM provider (spec §15). Falls back to the deterministic fake
  # adapter when no real credentials are present, so dev/test run offline.
  def llm
    @llm ||= build_llm
  end

  # The configured image provider (spec §15).
  def image
    @image ||= build_image
  end

  # The configured voice/TTS provider (spec §15, §26).
  def voice
    @voice ||= build_voice
  end

  # The vision reviewer used by the quality_check stage (Task 6). Free-tier only
  # by default, like every other provider here.
  def qa
    @qa ||= build_qa
  end

  # Test hooks.
  def llm=(adapter)
    @llm = adapter
  end

  def image=(adapter)
    @image = adapter
  end

  def voice=(adapter)
    @voice = adapter
  end

  def qa=(adapter)
    @qa = adapter
  end

  def reset!
    @llm = nil
    @image = nil
    @voice = nil
    @qa = nil
  end

  def build_llm
    provider = ENV["LLM_PROVIDER"].presence
    provider ||= "groq" if ENV["GROQ_API_KEY"].present?
    provider ||= "anthropic" if ENV["ANTHROPIC_API_KEY"].present?
    provider ||= "gemini" if ENV["GEMINI_API_KEY"].present?
    provider ||= "fake"

    adapter = case provider
    when "groq" then LLM::GroqAdapter.new
    when "anthropic" then LLM::AnthropicAdapter.new
    when "gemini" then LLM::GeminiAdapter.new
    when "fake" then LLM::FakeAdapter.new
    else raise ArgumentError, "unknown LLM_PROVIDER: #{provider.inspect}"
    end
    guard_paid!("LLM", adapter.name, adapter.default_model)
    adapter
  end

  def allow_paid_providers?
    ENV["ALLOW_PAID_PROVIDERS"] == "true"
  end

  # Refuses a paid provider/model unless ALLOW_PAID_PROVIDERS=true (Task 5B).
  def guard_paid!(kind, provider, model)
    return if allow_paid_providers?
    return unless Pricing.paid?(provider, model)

    raise PaidProviderBlocked,
      "#{kind} provider #{provider}/#{model} is a paid model and paid providers are blocked. " \
      "Set ALLOW_PAID_PROVIDERS=true in apps/api/.env to allow paid usage (default: false)."
  end

  def build_image
    provider = ENV["IMAGE_PROVIDER"].presence
    provider ||= "cloudflare" if ENV["CLOUDFLARE_API_TOKEN"].present?
    provider ||= "gemini" if ENV["GEMINI_API_KEY"].present? && ENV["GEMINI_IMAGE_ENABLED"].present?
    provider ||= "fake"

    adapter = case provider
    when "gemini" then Image::GeminiAdapter.new
    when "cloudflare" then Image::CloudflareAdapter.new
    when "pollinations" then Image::PollinationsAdapter.new
    when "fake" then Image::FakeImageAdapter.new
    else raise ArgumentError, "unknown IMAGE_PROVIDER: #{provider.inspect}"
    end
    guard_paid!("image", adapter.name, adapter.default_model)
    return CappedImageAdapter.new(adapter) if Pricing.paid?(adapter.name, adapter.default_model)

    adapter
  end

  def build_voice
    provider = ENV["VOICE_PROVIDER"].presence
    provider ||= "elevenlabs" if ENV["ELEVENLABS_API_KEY"].present?
    provider ||= "fake"

    adapter = case provider
    when "elevenlabs" then Voice::ElevenLabsAdapter.new
    when "edge_tts", "edge" then Voice::EdgeTtsAdapter.new
    when "gemini_tts", "gemini" then Voice::GeminiTtsAdapter.new
    when "fake" then Voice::FakeVoiceAdapter.new
    else raise ArgumentError, "unknown VOICE_PROVIDER: #{provider.inspect}"
    end
    guard_paid!("voice", adapter.name, adapter.default_model)
    adapter
  end

  def build_qa
    provider = ENV["QA_PROVIDER"].presence
    provider ||= "gemini" if ENV["GEMINI_API_KEY"].present?
    provider ||= "fake"

    adapter = case provider
    when "gemini" then Qa::GeminiVisionAdapter.new
    when "fake" then Qa::FakeAdapter.new
    else raise ArgumentError, "unknown QA_PROVIDER: #{provider.inspect}"
    end
    guard_paid!("QA", adapter.name, adapter.default_model)
    adapter
  end
end
