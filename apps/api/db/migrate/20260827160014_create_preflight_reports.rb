class CreatePreflightReports < ActiveRecord::Migration[8.1]
  def change
    # YouTube-oriented preflight (spec §32). Internal heuristic — never a
    # monetization guarantee.
    create_table :preflight_reports do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true
      t.references :video_render, foreign_key: true, index: true
      t.references :generated_by_generation, foreign_key: { to_table: :ai_generations }, index: true

      t.string  :status, null: false, default: "review_required" # ready|review_required
      t.jsonb   :checks, null: false, default: {}   # {originality: "pass", narrative_value: "warn", ...}
      t.string  :ai_disclosure, null: false, default: "review" # required|not_required|review
      t.jsonb   :warnings, null: false, default: []

      t.datetime :acknowledged_at
      t.references :acknowledged_by, foreign_key: { to_table: :users }, index: true

      t.timestamps
    end
    add_index :preflight_reports, :public_id, unique: true
    add_index :preflight_reports, [ :project_id, :created_at ]
  end
end
