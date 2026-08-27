module Providers
  module_function

  # The configured LLM provider (spec §15). Falls back to the deterministic fake
  # adapter when no real credentials are present, so dev/test run offline.
  def llm
    @llm ||= build_llm
  end

  # Test hook.
  def llm=(adapter)
    @llm = adapter
  end

  def reset!
    @llm = nil
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
end
