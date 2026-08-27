module Providers
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

  def reset!
    @llm = nil
    @image = nil
    @voice = nil
  end

  def build_llm
    provider = ENV["LLM_PROVIDER"].presence
    provider ||= ENV["ANTHROPIC_API_KEY"].present? ? "anthropic" : "fake"

    case provider
    when "anthropic" then LLM::AnthropicAdapter.new
    when "fake" then LLM::FakeAdapter.new
    else raise ArgumentError, "unknown LLM_PROVIDER: #{provider.inspect}"
    end
  end

  def build_image
    provider = ENV["IMAGE_PROVIDER"].presence
    provider ||= ENV["GEMINI_API_KEY"].present? ? "gemini" : "fake"

    case provider
    when "gemini" then Image::GeminiAdapter.new
    when "fake" then Image::FakeImageAdapter.new
    else raise ArgumentError, "unknown IMAGE_PROVIDER: #{provider.inspect}"
    end
  end

  def build_voice
    provider = ENV["VOICE_PROVIDER"].presence
    provider ||= ENV["ELEVENLABS_API_KEY"].present? ? "elevenlabs" : "fake"

    case provider
    when "elevenlabs" then Voice::ElevenLabsAdapter.new
    when "fake" then Voice::FakeVoiceAdapter.new
    else raise ArgumentError, "unknown VOICE_PROVIDER: #{provider.inspect}"
    end
  end
end
