class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :public_id, null: false
      t.references :user, null: false, foreign_key: true, index: true

      t.string  :title, null: false, default: "Untitled project"
      t.text    :topic
      t.string  :format, null: false, default: "youtube_long" # youtube_long | youtube_short | reel
      t.string  :aspect_ratio, null: false, default: "16:9"
      t.string  :niche
      t.string  :audience
      t.string  :tone
      t.integer :target_duration_seconds, null: false, default: 120
      t.text    :creator_instructions

      # Template pinned at generation time (spec §24)
      t.references :template, foreign_key: true, index: true
      t.bigint  :template_version_id
      t.index   :template_version_id

      # Lifecycle (spec §18) — managed by AASM
      t.string  :status, null: false, default: "draft"
      t.boolean :research_enabled, null: false, default: false
      t.text    :failure_reason
      t.datetime :completed_at
      t.datetime :cancelled_at

      t.jsonb   :settings, null: false, default: {}   # voice, advanced options
      t.jsonb   :disclosure, null: false, default: {} # project-level AI-disclosure rollup (spec §7)
      t.jsonb   :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :projects, :public_id, unique: true
    add_index :projects, [ :user_id, :status ]
    add_index :projects, :created_at

    add_foreign_key :projects, :template_versions, column: :template_version_id, on_delete: :nullify
  end
end
