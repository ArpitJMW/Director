# Force the deterministic LLM adapter in tests regardless of local env.
RSpec.configure do |config|
  config.before do
    Providers.llm = Providers::LLM::FakeAdapter.new
  end

  config.after do
    Providers.reset!
  end
end
