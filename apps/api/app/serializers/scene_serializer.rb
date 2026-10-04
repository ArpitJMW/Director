class SceneSerializer < ApplicationSerializer
  def as_json
    voice = record.current_voice_generation

    {
      id: record.public_id,
      project_id: record.project.public_id,
      status: record.status,
      position: record.position,
      notes: record.notes,
      failure_reason: record.failure_reason,
      # The Scene JSON contract (spec §19), inlined.
      scene: record.to_scene_json,
      selected_asset: AssetSerializer.call(record.selected_asset),
      narration_audio: voice && {
        url: voice.audio_asset&.signed_url,
        duration_seconds: voice.duration_seconds&.to_f,
        provider: voice.provider
      },
      captions: voice&.captions || [],
      qa: qa_summary,
      needs_regeneration: record.needs_regeneration?,
      needs_rerender: record.needs_rerender?,
      created_at: ts(record.created_at),
      updated_at: ts(record.updated_at)
    }
  end

  private

  # Task 6 Part E: the scene's own QA state, rolled up with its shots' so the
  # scene card can show one badge. Read from metadata; no extra provider work.
  def qa_summary
    units = [ record, *record.shots.to_a ]
    states = units.filter_map { |u| u.metadata&.dig("qa") }
    return nil if states.empty?

    status = if states.any? { |q| q["status"] == "failed" } then "failed"
             elsif states.any? { |q| q["status"] == "unavailable" } then "unavailable"
             else "passed"
             end
    repair = units.filter_map { |u| u.metadata&.dig("qa", "repair") }.last
    {
      status: status,
      issues: states.flat_map { |q| q["issues"].to_a }.map do |i|
        i.slice("issue_type", "severity", "evidence", "source")
      end,
      repaired: repair&.dig("outcome") == "repaired",
      repair_outcome: repair&.dig("outcome")
    }
  end
end
