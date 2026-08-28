class AddVisualStyleToProjects < ActiveRecord::Migration[8.1]
  def change
    # Drives the look of every generated image (spec §24 — templates define
    # visual identity; this is the per-project override).
    add_column :projects, :visual_style, :string, null: false, default: "cinematic"
    # Deterministic per project so all scenes share one visual "family".
    add_column :projects, :image_seed, :integer
  end
end
