class ProjectSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      title: record.title,
      topic: record.topic,
      status: record.status,
      format: record.format,
      visual_style: record.visual_style,
      aspect_ratio: record.aspect_ratio,
      niche: record.niche,
      audience: record.audience,
      tone: record.tone,
      target_duration_seconds: record.target_duration_seconds,
      creator_instructions: record.creator_instructions,
      research_enabled: record.research_enabled,
      failure_reason: record.failure_reason,
      settings: record.settings,
      disclosure: record.disclosure,
      template_id: record.template&.public_id,
      scene_count: record.scenes.size,
      pending_render_changes: pending_render_changes?,
      pipeline: {
        mode: record.pipeline_mode,
        checkpoint: record.pipeline_checkpoint,
        active_stage: record.generation_jobs.active.where(scene_id: nil).order(:created_at).last&.stage
      },
      created_at: ts(record.created_at),
      updated_at: ts(record.updated_at),
      completed_at: ts(record.completed_at)
    }.tap do |hash|
      hash[:current_script] = ScriptSerializer.call(record.current_script) if opts[:include_script]
      hash[:scenes] = SceneSerializer.list(record.scenes) if opts[:include_scenes]
      hash[:qa] = qa_summary if opts[:include_scenes]
      hash[:cost] = { estimate: Providers::CostReport.estimate(record), actual: Providers::CostReport.actual(record) } if opts[:include_cost]
    end
  end

  private

  # Task 6 Part E: project-level QA roll-up, read from each unit's metadata.
  def qa_summary
    units = record.scenes.includes(:shots).flat_map { |s| [ s, *s.shots.to_a ] }
    states = units.filter_map { |u| u.metadata&.dig("qa") }
    return { checked: false, setting: record.settings.to_h["setting"].present? } if states.empty?

    {
      checked: true,
      setting: record.settings.to_h["setting"].present?,
      units: states.size,
      passed: states.count { |q| q["status"] == "passed" },
      failed: states.count { |q| q["status"] == "failed" },
      unavailable: states.count { |q| q["status"] == "unavailable" },
      repaired: units.count { |u| u.metadata&.dig("qa", "repair", "outcome") == "repaired" },
      issues: states.sum { |q| q["issues"].to_a.size }
    }
  end

  # Phase 1 Task 3: single aggregate query (rather than each scene running
  # its own Scene#needs_rerender? against the project) — true when ANY scene
  # was touched by a direction-only edit since the last completed render.
  def pending_render_changes?
    last_rendered_at = record.video_renders.where(status: "completed").maximum(:finished_at)
    return false if last_rendered_at.nil?

    record.scenes.where("scenes.updated_at > ?", last_rendered_at).exists?
  end
end
