class VideoRenderSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      version: record.version,
      status: record.status,
      renderer: record.renderer,
      progress: record.progress,
      width: record.width,
      height: record.height,
      fps: record.fps,
      duration_seconds: record.duration_seconds&.to_f,
      output_url: record.output_asset&.signed_url,
      render_seconds: record.render_seconds&.to_f,
      cost_usd: record.cost_usd.to_f,
      failure_reason: record.failure_reason,
      started_at: ts(record.started_at),
      finished_at: ts(record.finished_at),
      created_at: ts(record.created_at)
    }
  end
end
