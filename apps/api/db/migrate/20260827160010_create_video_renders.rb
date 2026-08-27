class CreateVideoRenders < ActiveRecord::Migration[8.1]
  def change
    create_table :video_renders do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true
      t.references :template_version, foreign_key: true, index: true
      t.references :output_asset, foreign_key: { to_table: :assets }, index: true

      t.integer :version, null: false, default: 1
      t.string  :status, null: false, default: "queued" # queued|rendering|uploading|completed|failed|cancelled
      t.string  :renderer, null: false, default: "remotion"

      t.jsonb   :manifest, null: false, default: {} # full render manifest (spec §20 step 14)

      t.integer :width
      t.integer :height
      t.integer :fps
      t.integer :frame_count
      t.decimal :duration_seconds, precision: 9, scale: 3
      t.integer :progress, null: false, default: 0

      t.datetime :started_at
      t.datetime :finished_at
      t.decimal :render_seconds, precision: 10, scale: 3 # spec §37
      t.decimal :cost_usd, precision: 12, scale: 6, null: false, default: 0

      t.text    :log
      t.text    :failure_reason
      t.jsonb   :error, null: false, default: {}

      t.timestamps
    end
    add_index :video_renders, :public_id, unique: true
    add_index :video_renders, [ :project_id, :version ], unique: true
  end
end
