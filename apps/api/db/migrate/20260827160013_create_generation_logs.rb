class CreateGenerationLogs < ActiveRecord::Migration[8.1]
  def change
    # Append-only structured log lines for a project's pipeline (spec §16, §37).
    create_table :generation_logs do |t|
      t.references :project, null: false, foreign_key: true, index: true
      t.references :generation_job, foreign_key: true, index: true
      t.references :ai_generation, foreign_key: true, index: true
      t.references :scene, foreign_key: true, index: true

      t.string  :level, null: false, default: "info" # debug|info|warn|error
      t.string  :stage
      t.text    :message, null: false
      t.jsonb   :data, null: false, default: {}

      t.datetime :created_at, null: false
    end
    add_index :generation_logs, [ :project_id, :created_at ]
    add_index :generation_logs, :level
  end
end
