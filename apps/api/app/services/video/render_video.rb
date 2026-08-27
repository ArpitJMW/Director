require "open3"
require "tmpdir"

module Video
  # Drives the external Remotion renderer (spec §14 video/render_video, §25).
  # Writes the manifest to a temp file, shells out to the renderer, and returns
  # the produced MP4 path. Kept behind an interface so the renderer can move to a
  # separate service later.
  class RenderVideo
    Error = Class.new(StandardError)

    # Overridable command; receives MANIFEST and OUTPUT env vars.
    def self.command
      ENV["RENDER_COMMAND"].presence ||
        "node #{Rails.root.join('../renderer/render.mjs')}"
    end

    def initialize(manifest:, command: self.class.command)
      @manifest = manifest
      @command = command
    end

    # @return [Hash] { path:, render_seconds:, bytes: }
    def call
      Dir.mktmpdir("clipify-render") do |dir|
        manifest_path = File.join(dir, "manifest.json")
        output_path = File.join(dir, "video.mp4")
        File.write(manifest_path, @manifest.to_json)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        run!(manifest_path, output_path)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        raise Error, "renderer produced no output" unless File.exist?(output_path)

        {
          path: output_path,
          render_seconds: elapsed.round(2),
          bytes: File.binread(output_path)
        }
      end
    end

    private

    def run!(manifest_path, output_path)
      env = { "MANIFEST" => manifest_path, "OUTPUT" => output_path }
      output, status = Open3.capture2e(env, *@command.split, manifest_path, output_path)
      raise Error, "renderer failed (#{status.exitstatus}): #{output.last(2000)}" unless status.success?
    end
  end
end
