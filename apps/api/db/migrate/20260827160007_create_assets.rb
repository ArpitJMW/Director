class CreateAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :assets do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true
      t.references :scene, foreign_key: true, index: true # null => project-level asset

      t.string  :asset_type, null: false # image|video|audio|music|logo|caption_file|thumbnail
      t.string  :storage_key
      t.string  :storage_url
      t.string  :content_type
      t.bigint  :byte_size
      t.string  :checksum
      t.integer :width
      t.integer :height
      t.decimal :duration_seconds, precision: 9, scale: 3

      # Generation metadata (spec §27)
      t.string  :provider
      t.string  :model
      t.text    :prompt
      t.string  :provider_request_id
      t.bigint  :ai_generation_id
      t.decimal :cost_usd, precision: 12, scale: 6, null: false, default: 0

      # Provenance & disclosure (spec §6, §7, §27)
      t.string  :source_type, null: false, default: "ai_generated" # ai_generated|user_provided|licensed|public_domain|stock|other
      t.string  :license
      t.jsonb   :provenance, null: false, default: {}
      t.boolean :ai_generated, null: false, default: false
      t.boolean :realistic, null: false, default: false
      t.boolean :represents_real_person, null: false, default: false
      t.boolean :represents_real_event_or_place, null: false, default: false
      t.boolean :requires_disclosure, null: false, default: false

      t.jsonb   :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :assets, :public_id, unique: true
    add_index :assets, :ai_generation_id
    add_index :assets, [ :project_id, :asset_type ]

    add_foreign_key :scenes, :assets, column: :selected_asset_id, on_delete: :nullify
    add_foreign_key :templates, :assets, column: :preview_asset_id, on_delete: :nullify
  end
end
