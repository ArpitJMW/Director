require "rails_helper"
require "chunky_png"
require "fastimage"

RSpec.describe Media::LetterboxCropper do
  # 1376x768 frame: top and bottom 15% pure black (letterbox), textured middle.
  def letterboxed_png(width: 1376, height: 768, bar: 0.15)
    band = (height * bar).round
    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
    height.times do |y|
      next if y < band || y >= height - band
      width.times do |x|
        v = (90 + 60 * Math.sin(x / 37.0) * Math.cos(y / 29.0) + (x % 7)).round.clamp(40, 200)
        png[x, y] = ChunkyPNG::Color.rgb(v, v, v)
      end
    end
    png.to_blob
  end

  def plain_png(width: 1376, height: 768)
    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE)
    height.times { |y| width.times { |x| png[x, y] = ChunkyPNG::Color.rgb((x * 3 + y) % 200 + 30, 90, 120) } }
    png.to_blob
  end

  def dims(bytes)
    FastImage.size(StringIO.new(bytes))
  end

  it "removes the black bars and cover-crops the result to 16:9" do
    input = letterboxed_png
    output = described_class.new(aspect_ratio: "16:9").call(bytes: input, content_type: "image/png")

    expect(output.cropped).to be true
    width, height = dims(output.bytes)
    expect(width.to_f / height).to be_within(0.01).of(16.0 / 9)
    expect(height).to be < 768 * 0.75 # both bars gone, not just one
  end

  it "reports the detected bar depths" do
    output = described_class.new(aspect_ratio: "16:9").call(bytes: letterboxed_png, content_type: "image/png")

    expect(output.info["bars"]["top"]).to be_within(3).of(115)
    expect(output.info["bars"]["bottom"]).to be_within(3).of(115)
  end

  it "is a byte-identical no-op on a normal image already at the target aspect" do
    input = plain_png
    output = described_class.new(aspect_ratio: "16:9").call(bytes: input, content_type: "image/png")

    expect(output.cropped).to be false
    expect(output.bytes).to eq(input)
  end

  it "raises a Media::LetterboxCropper::Error for bytes it cannot decode" do
    expect { described_class.new(aspect_ratio: "16:9").call(bytes: "not an image", content_type: "image/png") }
      .to raise_error(Media::LetterboxCropper::Error)
  end

  it "rejects a malformed aspect ratio" do
    expect { described_class.new(aspect_ratio: "wide") }.to raise_error(ArgumentError)
  end
end
