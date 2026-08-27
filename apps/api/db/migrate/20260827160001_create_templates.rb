class CreateTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :templates do |t|
      t.string  :public_id, null: false
      t.string  :slug, null: false
      t.string  :name, null: false
      t.text    :description
      t.string  :category
      t.string  :status, null: false, default: "draft"
      t.references :owner, foreign_key: { to_table: :users }, index: true # null => built-in
      t.bigint  :latest_version_id # FK added after template_versions exists
      t.bigint  :preview_asset_id  # FK added after assets exists
      t.timestamps
    end
    add_index :templates, :public_id, unique: true
    add_index :templates, :slug, unique: true

    create_table :template_versions do |t|
      t.string :public_id, null: false
      t.references :template, null: false, foreign_key: true, index: true
      t.integer :version, null: false, default: 1
      # typography, colors, caption/animation/transition/audio rules,
      # scene presets, thumbnail style (spec §24)
      t.jsonb   :config, null: false, default: {}
      t.text    :changelog
      t.datetime :published_at
      t.timestamps
    end
    add_index :template_versions, :public_id, unique: true
    add_index :template_versions, [ :template_id, :version ], unique: true

    add_foreign_key :templates, :template_versions, column: :latest_version_id, on_delete: :nullify
    add_index :templates, :latest_version_id
  end
end
