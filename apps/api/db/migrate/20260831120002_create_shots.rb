class CreateShots < ActiveRecord::Migration[8.1]
  # Phase A (spec §6/§7). A scene may contain one or more camera shots. Each shot
  # is the smallest visual unit that gets generated and rendered. Scenes with no
  # shots keep rendering exactly as before (scene-level selected_asset).
  def change
    create_table :shots do |t|
      t.references :scene, null: false, foreign_key: true
      t.references :selected_asset, foreign_key: { to_table: :assets }
      t.string  :public_id, null: false
      t.string  :key, null: false                     # e.g. "scene_02_shot_1"
      t.integer :position, null: false
      t.decimal :duration_seconds, precision: 6, scale: 2, default: "4.0", null: false

      t.string  :shot_type, default: "static", null: false  # wide|establishing|medium|close_up|tracking|push_in|pull_out|pan|tilt|top_down|static|screen|chart
      t.string  :camera_movement
      t.string  :framing
      t.text    :action

      t.string  :visual_type, default: "image", null: false  # mirrors Scene::VISUAL_TYPES
      t.string  :content_type
      t.string  :asset_strategy, default: "image", null: false
      t.text    :visual_prompt
      t.text    :negative_prompt
      t.jsonb   :motion, default: {}, null: false

      t.string  :status, default: "pending", null: false
      t.text    :failure_reason
      t.jsonb   :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :shots, :public_id, unique: true
    add_index :shots, [ :scene_id, :position ], unique: true
    add_index :shots, [ :scene_id, :key ], unique: true

    # Let generated assets and provider calls attribute to a shot (nullable —
    # scene-level generation still works with shot_id NULL).
    add_reference :assets, :shot, foreign_key: true
    add_reference :ai_generations, :shot, foreign_key: true
  end
end
