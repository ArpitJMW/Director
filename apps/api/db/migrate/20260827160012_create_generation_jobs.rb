class CreateGenerationJobs < ActiveRecord::Migration[8.1]
  def change
    # A retryable unit of pipeline work (spec §20, §28). Wraps a Sidekiq job and
    # records idempotency, attempts and fan-out structure.
    create_table :generation_jobs do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true
      t.references :scene, foreign_key: true, index: true
      t.references :parent_job, foreign_key: { to_table: :generation_jobs }, index: true

      t.string  :stage, null: false  # validate|research|collect_sources|story_angle|script|fact_check|storyboard|visual_direction|prompts|assets|narration|captions|music|manifest|render|quality_check|preflight|finalize
      t.string  :status, null: false, default: "pending" # pending|queued|running|succeeded|failed|cancelled|retrying
      t.string  :queue, null: false, default: "default"
      t.string  :sidekiq_jid
      t.string  :idempotency_key, null: false

      t.integer :attempts, null: false, default: 0
      t.integer :max_attempts, null: false, default: 3
      t.integer :progress, null: false, default: 0

      t.jsonb   :args, null: false, default: {}
      t.jsonb   :result, null: false, default: {}
      t.jsonb   :error, null: false, default: {}
      t.text    :failure_reason

      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :generation_jobs, :public_id, unique: true
    add_index :generation_jobs, :idempotency_key, unique: true
    add_index :generation_jobs, [ :project_id, :stage ]
    add_index :generation_jobs, :status
  end
end
