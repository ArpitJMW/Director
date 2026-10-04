class AddSceneDirectionFields < ActiveRecord::Migration[8.1]
  # Phase A of the Visual Intelligence upgrade (AI video planning spec §5/§6).
  # A scene stops being "one sentence = one image": it now carries production
  # direction (purpose, action, camera intent, mood, medium strategy) and can be
  # subdivided into shots. All columns are nullable / defaulted so existing
  # scenes and the current render path are unaffected.
  def change
    change_table :scenes, bulk: true do |t|
      t.text    :purpose
      t.string  :content_type                       # visual treatment for this beat; nil => project.visual_style
      t.text    :action                             # what happens visually
      t.jsonb   :camera,         default: {}, null: false  # { shot_type, movement, framing }
      t.jsonb   :motion,         default: {}, null: false  # { subject, environment, background }
      t.string  :mood
      t.string  :asset_strategy, default: "image", null: false # image | image_to_video | animation | chart | text | screen | user_asset | mixed
      t.text    :negative_prompt
      t.jsonb   :character_ids,  default: [], null: false     # loose refs until Phase C adds the Character model
      t.bigint  :environment_id                               # loose ref until Phase C (no FK yet)
    end
  end
end
