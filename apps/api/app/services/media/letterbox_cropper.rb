require "open3"
require "tmpdir"

module Media
  # Task 5C: strips baked-in black letterbox bars from a generated image and
  # centre-crops it to the project's aspect ratio. The work happens in
  # apps/renderer/letterbox-crop.mjs (sharp decodes the JPEG/PNG providers
  # actually return; nothing else in this stack can). A normal image comes back
  # byte-for-byte unchanged.
  class LetterboxCropper
    Error = Class.new(StandardError)

    SCRIPT = Rails.root.join("..", "renderer", "letterbox-crop.mjs").expand_path.to_s
    EXTENSIONS = { "image/jpeg" => ".jpg", "image/webp" => ".webp" }.freeze

    Output = Data.define(:bytes, :cropped, :info)

    def initialize(aspect_ratio:)
      @width, @height = aspect_ratio.to_s.split(":").map(&:to_i)
      raise ArgumentError, "bad aspect ratio #{aspect_ratio.inspect}" unless @width.to_i.positive? && @height.to_i.positive?
    end

    def call(bytes:, content_type:)
      Dir.mktmpdir("letterbox") do |dir|
        ext = EXTENSIONS.fetch(content_type.to_s, ".png")
        input = File.join(dir, "in#{ext}")
        output = File.join(dir, "out#{ext}")
        File.binwrite(input, bytes)

        stdout, stderr, status = Open3.capture3("node", SCRIPT, input, output, @width.to_s, @height.to_s)
        raise Error, "letterbox crop failed: #{stderr.presence || stdout}" unless status.success?

        info = JSON.parse(stdout)
        return Output.new(bytes: bytes, cropped: false, info: info) unless info["cropped"]

        Output.new(bytes: File.binread(output), cropped: true, info: info)
      end
    end
  end
end
