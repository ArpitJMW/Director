class AddCaptionsToVoiceGenerations < ActiveRecord::Migration[8.1]
  def change
    # Timed caption cues derived from the TTS alignment (spec §26):
    # [{ "text": "...", "start": 0.0, "end": 2.4 }, ...]
    add_column :voice_generations, :captions, :jsonb, null: false, default: []
    add_column :voice_generations, :model, :string unless column_exists?(:voice_generations, :model)
  end
end
