class CreateMusicTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :music_tracks do |t|
      t.string :public_id, null: false
      t.references :project, foreign_key: true, index: true # null => shared library track
      t.references :asset, foreign_key: true, index: true

      t.string  :title
      t.string  :provider
      t.string  :source_type, null: false, default: "licensed" # ai_generated|licensed|public_domain|stock
      t.string  :license
      t.string  :mood
      t.integer :bpm
      t.decimal :duration_seconds, precision: 9, scale: 3

      t.jsonb   :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :music_tracks, :public_id, unique: true
  end
end
