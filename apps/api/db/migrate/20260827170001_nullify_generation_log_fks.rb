class NullifyGenerationLogFks < ActiveRecord::Migration[8.1]
  # generation_logs are append-only history tied to the project. When a scene,
  # job or ai_generation they reference is removed (e.g. storyboard regeneration),
  # keep the log and null the reference rather than blocking the delete.
  REFS = { scene_id: :scenes, generation_job_id: :generation_jobs, ai_generation_id: :ai_generations }.freeze

  def up
    REFS.each do |column, table|
      remove_foreign_key :generation_logs, table, column: column
      add_foreign_key :generation_logs, table, column: column, on_delete: :nullify
    end
  end

  def down
    REFS.each do |column, table|
      remove_foreign_key :generation_logs, table, column: column
      add_foreign_key :generation_logs, table, column: column
    end
  end
end
