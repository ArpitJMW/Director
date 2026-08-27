class PreflightReportSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      status: record.status,
      checks: record.checks,
      ai_disclosure: record.ai_disclosure,
      warnings: record.warnings,
      acknowledged_at: ts(record.acknowledged_at),
      acknowledged_by: record.acknowledged_by&.public_id,
      video_render_id: record.video_render&.public_id,
      created_at: ts(record.created_at),
      # Never a guarantee of YouTube monetization (spec §32).
      disclaimer: "Internal heuristic only. Not an official YouTube score or a monetization guarantee."
    }
  end
end
