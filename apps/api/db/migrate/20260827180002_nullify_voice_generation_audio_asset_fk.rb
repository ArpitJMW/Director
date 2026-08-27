class NullifyVoiceGenerationAudioAssetFk < ActiveRecord::Migration[8.1]
  # Let an audio asset be removed without blocking on the voice_generation that
  # points at it (the voice_generation is torn down alongside its scene anyway).
  def up
    remove_foreign_key :voice_generations, :assets, column: :audio_asset_id
    add_foreign_key :voice_generations, :assets, column: :audio_asset_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :voice_generations, :assets, column: :audio_asset_id
    add_foreign_key :voice_generations, :assets, column: :audio_asset_id
  end
end
