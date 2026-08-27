class CreateScenes < ActiveRecord::Migration[8.1]
  def change
    create_table :scenes do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true
      t.references :script, foreign_key: true, index: true

      # Scene JSON contract (spec §19)
      t.string  :key, null: false                        # "scene_01"
      t.integer :position, null: false
      t.decimal :duration_seconds, precision: 6, scale: 2, null: false, default: 5
      t.text    :narration
      t.string  :visual_type, null: false, default: "image" # spec §23
      t.text    :visual_prompt
      t.text    :caption
      t.string  :animation, null: false, default: "ken_burns" # spec §25
      t.string  :transition, null: false, default: "fade"
      t.decimal :background_music_level, precision: 4, scale: 2, null: false, default: 0.15

      t.bigint  :selected_asset_id # FK added in a later migration (circular with assets)
      t.index   :selected_asset_id

      # Per-scene lifecycle so a single scene can be regenerated (spec §28)
      t.string  :status, null: false, default: "pending"
      t.text    :failure_reason
      t.text    :notes            # creator scene corrections
      t.jsonb   :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :scenes, :public_id, unique: true
    add_index :scenes, [ :project_id, :position ], unique: true
    add_index :scenes, [ :project_id, :key ], unique: true
  end
end
