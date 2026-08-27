class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true, index: true

      t.string  :url
      t.string  :title
      t.string  :publisher
      t.date    :published_on
      t.datetime :accessed_at

      t.text    :summary                         # generated interpretation
      t.text    :raw_excerpt                      # verbatim source text, kept separate (spec §21)
      t.jsonb   :extracted_claims, null: false, default: []

      t.string  :reliability, null: false, default: "unknown" # unknown|low|medium|high
      t.string  :provided_by, null: false, default: "user"    # user|research_engine

      t.jsonb   :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :sources, :public_id, unique: true
  end
end
