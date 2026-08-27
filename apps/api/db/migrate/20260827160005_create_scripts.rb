class CreateScripts < ActiveRecord::Migration[8.1]
  def change
    create_table :scripts do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true

      t.integer :version, null: false, default: 1
      t.boolean :current, null: false, default: true

      t.jsonb   :title_options, null: false, default: [] # spec §22 outputs
      t.string  :selected_title
      t.text    :hook
      t.text    :story_angle
      t.jsonb   :sections, null: false, default: []      # [{heading, narration, ...}]
      t.text    :full_narration
      t.integer :estimated_duration_seconds
      t.text    :creative_notes
      t.string  :tone

      # Provenance (spec §6, §27)
      t.string  :source_type, null: false, default: "ai_generated" # ai_generated|user_provided|ai_edited
      t.jsonb   :claims, null: false, default: []                   # [{text, source_ids:[]}]
      t.bigint  :ai_generation_id
      t.index   :ai_generation_id

      t.timestamps
    end
    add_index :scripts, :public_id, unique: true
    add_index :scripts, [ :project_id, :version ], unique: true
    add_index :scripts, [ :project_id, :current ], unique: true, where: "current"
  end
end
