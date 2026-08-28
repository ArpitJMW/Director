class NullifyRemainingAssetFks < ActiveRecord::Migration[8.1]
  # These references block project.destroy because of association teardown order.
  # Nullify on delete — the owning record is torn down alongside its project
  # anyway.
  FKS = [
    [ :video_renders, :assets, :output_asset_id ],
    [ :preflight_reports, :video_renders, :video_render_id ],
    [ :preflight_reports, :ai_generations, :generated_by_generation_id ],
    [ :music_tracks, :assets, :asset_id ]
  ].freeze

  def up
    FKS.each do |from, to, column|
      remove_foreign_key from, to, column: column
      add_foreign_key from, to, column: column, on_delete: :nullify
    end
  end

  def down
    FKS.each do |from, to, column|
      remove_foreign_key from, to, column: column
      add_foreign_key from, to, column: column
    end
  end
end
