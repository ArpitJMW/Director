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
      created_at: ts(record.created_at),
      updated_at: ts(record.updated_at)
    }
  end
end
