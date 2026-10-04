module Providers
  module Qa
    # Deterministic stand-in for the vision reviewer (tests and offline dev).
    # Answers with whatever reply it was built with, so parsing and repair logic
    # can be exercised without any network call.
    class FakeAdapter
      def initialize(reply: '{"issues": []}', error: nil, batch_reply: nil)
        @reply = reply
        @error = error
        @batch_reply = batch_reply
      end

      def name = "fake"
      def default_model = "fake-vision-1"

      def review(image_bytes:, content_type:, prompt:)
        reply_for(@reply)
      end

      # Batch replies are built by the caller's block when given, so a spec can
      # answer each image id explicitly (or leave one out to test the fallback).
      def review_batch(images:, prompt:)
        reply_for(@batch_reply || '{"results": []}', images)
      end

      def reply_for(text, _images = nil)
        raise @error if @error

        LLM::Result.new(
          text: text, model: default_model, provider: name, stop_reason: "stop",
          usage: { input_tokens: 0, output_tokens: 0 }, provider_request_id: nil,
          raw: { estimated_cost_usd: 0.0 }
        )
      end
    end
  end
end
