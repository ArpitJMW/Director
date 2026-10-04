module Generation
  # Stage: render the final MP4 (spec §20 step 15, §28). Never holds an HTTP
  # request open — the controller returns immediately and this runs in Sidekiq.
  class RenderJob < BaseJob
    sidekiq_options queue: "render", retry: 2

    def run(gen_job)
      project = gen_job.project
      video_render = project.video_renders.create!(
        template_version: project.template_version || project.template&.latest_version,
        width: dimensions(project).first, height: dimensions(project).last, fps: 30
      )
      gen_job.update!(result: { video_render_id: video_render.public_id })

      manifest = Media::RenderManifestBuilder.new(project: project, video_render: video_render).call
      video_render.update!(manifest: manifest)
      warn_about_silent_scenes(project, video_render, gen_job, manifest)
      video_render.start!

      result = Video::RenderVideo.new(manifest: manifest).call
      video_render.start_upload!

      asset = Asset.store!(
        project: project, asset_type: "video",
        io: StringIO.new(result[:bytes]), content_type: "video/mp4",
        source_type: "ai_generated", provider: "remotion",
        duration_seconds: total_duration(manifest)
      )

      video_render.update!(
        output_asset: asset,
        render_seconds: result[:render_seconds],
        duration_seconds: total_duration(manifest)
      )
      video_render.complete!

      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "info", stage: "render",
        message: "Rendered #{asset.byte_size} byte MP4 in #{result[:render_seconds]}s"
      )
    rescue => e
      project.video_renders.where(status: %w[queued rendering uploading]).find_each do |vr|
        vr.update(failure_reason: e.message)
        vr.mark_failed! if vr.may_mark_failed?
      end
      raise
    end

    private

    def dimensions(project)
      Media::RenderManifestBuilder::DIMENSIONS.fetch(
        project.aspect_ratio, Media::RenderManifestBuilder::DIMENSIONS["16:9"]
      )
    end

    def total_duration(manifest)
      manifest[:scenes].sum { |s| s[:duration].to_f }.round(2)
    end

    # Phase 1 Task 2.4 render safety: a narrated scene can still reach render
    # time with no audio (e.g. voice quota ran out and a retry hasn't happened
    # yet) — that must never render silently with no trace. Never blocks the
    # render; just makes the gap visible in two existing places rather than
    # only inside the scene data no one is looking at.
    def warn_about_silent_scenes(project, video_render, gen_job, manifest)
      silent = manifest[:scenes].select { |s| s[:narration].present? && s[:narration_audio_url].nil? }
      return if silent.empty?

      message = "#{silent.size} scene(s) have narration but no audio and will render silent: " \
                "#{silent.map { |s| s[:id] }.join(', ')}"
      video_render.update!(log: message)
      GenerationLog.create!(
        project: project, generation_job: gen_job, level: "warn",
        stage: "render", message: message
      )
    end
  end
end
