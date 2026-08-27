class AssetSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      asset_type: record.asset_type,
      url: record.storage_url,
      content_type: record.content_type,
      width: record.width,
      height: record.height,
      duration_seconds: record.duration_seconds&.to_f,
      provider: record.provider,
      model: record.model,
      prompt: record.prompt,
      cost_usd: record.cost_usd.to_f,
      source_type: record.source_type,
      license: record.license,
      ai_generated: record.ai_generated,
      realistic: record.realistic,
      represents_real_person: record.represents_real_person,
      represents_real_event_or_place: record.represents_real_event_or_place,
      requires_disclosure: record.requires_disclosure,
      scene_id: record.scene&.public_id,
      created_at: ts(record.created_at)
    }
  end
end
