class GenerationJobSerializer < ApplicationSerializer
  def as_json
    {
      id: record.public_id,
      stage: record.stage,
      status: record.status,
      progress: record.progress,
      attempts: record.attempts,
      max_attempts: record.max_attempts,
      active: GenerationJob::ACTIVE_STATUSES.include?(record.status),
      result: record.result,
      failure_reason: record.failure_reason,
      scene_id: record.scene&.public_id,
      created_at: ts(record.created_at),
      started_at: ts(record.started_at),
      finished_at: ts(record.finished_at)
    }
  end
end
