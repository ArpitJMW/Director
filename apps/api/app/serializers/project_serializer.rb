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
    end
  end
end
