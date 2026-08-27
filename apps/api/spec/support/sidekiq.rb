require "sidekiq/testing"

RSpec.configure do |config|
  config.before do
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all
  end

  # Tag an example with `:inline_jobs` to run enqueued jobs synchronously.
  config.around(:each, :inline_jobs) do |example|
    Sidekiq::Testing.inline! { example.run }
  end
end
