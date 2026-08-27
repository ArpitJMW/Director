class TemplateVersionSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      version: record.version,
      config: record.config,
      changelog: record.changelog,
      published_at: ts(record.published_at)
    }
  end
end
