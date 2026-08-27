class ScriptSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      version: record.version,
      current: record.current,
      selected_title: record.selected_title,
      title_options: record.title_options,
      hook: record.hook,
      story_angle: record.story_angle,
      sections: record.sections,
      full_narration: record.full_narration,
      estimated_duration_seconds: record.estimated_duration_seconds,
      creative_notes: record.creative_notes,
      source_type: record.source_type,
      claims: record.claims,
      created_at: ts(record.created_at),
      updated_at: ts(record.updated_at)
    }
  end
end
