module Providers
  # Wraps a paid image adapter so every generate call passes the cap first.
  class CappedImageAdapter
    def initialize(adapter)
      @adapter = adapter
    end

    def name = @adapter.name
    def default_model = @adapter.default_model

    def generate(**kwargs)
      PaidImageCap.reserve!(provider: name, model: default_model)
      @adapter.generate(**kwargs)
    end

    def method_missing(name, *args, **kwargs, &block)
      @adapter.public_send(name, *args, **kwargs, &block)
    end

    def respond_to_missing?(name, include_private = false) = @adapter.respond_to?(name, include_private) || super
  end
end
