module Providers
  module Image
    # Interface for image providers (spec §15).
    class Base
      Error = Class.new(StandardError)

      DIMENSIONS = {
        "16:9" => [ 1280, 720 ],
        "9:16" => [ 720, 1280 ],
        "1:1" => [ 1024, 1024 ]
      }.freeze

      # @param negative_prompt [String, nil] things to avoid (provider support varies)
      # @param seed [Integer, nil] for run-to-run visual consistency
      # @return [Providers::Image::Result]
      def generate(prompt:, aspect_ratio: "16:9", negative_prompt: nil, seed: nil, model: nil)
        raise NotImplementedError
      end

      def name = raise NotImplementedError
      def default_model = raise NotImplementedError

      protected

      def dimensions_for(aspect_ratio)
        DIMENSIONS.fetch(aspect_ratio, DIMENSIONS["16:9"])
      end
    end
  end
end
