class CreateVoiceGenerations < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_generations do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true
      t.references :scene, foreign_key: true, index: true
      t.references :script, foreign_key: true, index: true

      t.string  :provider, null: false, default: "elevenlabs"
      t.string  :voice_id
      t.string  :voice_name
      t.string  :model
      t.text    :text                                  # narration submitted to TTS
      t.references :audio_asset, foreign_key: { to_table: :assets }, index: true
      t.jsonb   :alignment, null: false, default: {}    # character/word timing (spec §26)

      t.string  :status, null: false, default: "pending"
      t.decimal :duration_seconds, precision: 9, scale: 3
      t.decimal :cost_usd, precision: 12, scale: 6, null: false, default: 0
      t.string  :provider_request_id
      t.bigint  :ai_generation_id
      t.index   :ai_generation_id
      t.text    :failure_reason

      t.timestamps
    end
    add_index :voice_generations, :public_id, unique: true
  end
end
