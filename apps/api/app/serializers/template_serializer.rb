class TemplateSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      slug: record.slug,
      name: record.name,
      description: record.description,
      category: record.category,
      status: record.status,
      built_in: record.owner_id.nil?,
      preview_url: record.preview_asset&.storage_url,
      latest_version: TemplateVersionSerializer.call(record.latest_version),
      created_at: ts(record.created_at)
    }
  end
end
