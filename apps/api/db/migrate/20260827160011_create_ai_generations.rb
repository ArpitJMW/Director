class CreateAiGenerations < ActiveRecord::Migration[8.1]
  def change
    # The provider-call ledger: one row per LLM / image / voice / music / video
    # call, with cost, tokens, latency and provenance (spec §16, §27, §37).
    create_table :ai_generations do |t|
      t.string :public_id, null: false
      t.references :project, foreign_key: true, index: true
      t.references :scene, foreign_key: true, index: true

      t.string  :kind, null: false      # research|script|scene_plan|visual_prompt|image|video|voice|caption|music|fact_check|quality_check|preflight
      t.string  :provider_kind, null: false, default: "llm" # llm|image|voice|music|video
      t.string  :provider, null: false
      t.string  :model

      t.string  :status, null: false, default: "pending" # pending|running|succeeded|failed
      t.jsonb   :request, null: false, default: {}   # sanitized params/prompt
      t.jsonb   :response, null: false, default: {}   # sanitized output

      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.bigint  :input_bytes
      t.bigint  :output_bytes
      t.decimal :cost_usd, precision: 12, scale: 6, null: false, default: 0
      t.integer :latency_ms

      t.string  :provider_request_id
      t.integer :attempt, null: false, default: 1
      t.integer :retry_count, null: false, default: 0
      t.text    :failure_reason
      t.jsonb   :error, null: false, default: {}

      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :ai_generations, :public_id, unique: true
    add_index :ai_generations, [ :project_id, :kind ]
    add_index :ai_generations, :provider_request_id

    add_foreign_key :scripts, :ai_generations, column: :ai_generation_id, on_delete: :nullify
    add_foreign_key :assets, :ai_generations, column: :ai_generation_id, on_delete: :nullify
    add_foreign_key :voice_generations, :ai_generations, column: :ai_generation_id, on_delete: :nullify
  end
end
