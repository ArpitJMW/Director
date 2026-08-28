# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_28_100001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ai_generations", force: :cascade do |t|
    t.integer "attempt", default: 1, null: false
    t.integer "completion_tokens"
    t.decimal "cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.jsonb "error", default: {}, null: false
    t.text "failure_reason"
    t.datetime "finished_at"
    t.bigint "input_bytes"
    t.string "kind", null: false
    t.integer "latency_ms"
    t.string "model"
    t.bigint "output_bytes"
    t.bigint "project_id"
    t.integer "prompt_tokens"
    t.string "provider", null: false
    t.string "provider_kind", default: "llm", null: false
    t.string "provider_request_id"
    t.string "public_id", null: false
    t.jsonb "request", default: {}, null: false
    t.jsonb "response", default: {}, null: false
    t.integer "retry_count", default: 0, null: false
    t.bigint "scene_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "total_tokens"
    t.datetime "updated_at", null: false
    t.index ["project_id", "kind"], name: "index_ai_generations_on_project_id_and_kind"
    t.index ["project_id"], name: "index_ai_generations_on_project_id"
    t.index ["provider_request_id"], name: "index_ai_generations_on_provider_request_id"
    t.index ["public_id"], name: "index_ai_generations_on_public_id", unique: true
    t.index ["scene_id"], name: "index_ai_generations_on_scene_id"
  end

  create_table "assets", force: :cascade do |t|
    t.boolean "ai_generated", default: false, null: false
    t.bigint "ai_generation_id"
    t.string "asset_type", null: false
    t.bigint "byte_size"
    t.string "checksum"
    t.string "content_type"
    t.decimal "cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "duration_seconds", precision: 9, scale: 3
    t.integer "height"
    t.string "license"
    t.jsonb "metadata", default: {}, null: false
    t.string "model"
    t.bigint "project_id", null: false
    t.text "prompt"
    t.jsonb "provenance", default: {}, null: false
    t.string "provider"
    t.string "provider_request_id"
    t.string "public_id", null: false
    t.boolean "realistic", default: false, null: false
    t.boolean "represents_real_event_or_place", default: false, null: false
    t.boolean "represents_real_person", default: false, null: false
    t.boolean "requires_disclosure", default: false, null: false
    t.bigint "scene_id"
    t.string "source_type", default: "ai_generated", null: false
    t.string "storage_key"
    t.string "storage_url"
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["ai_generation_id"], name: "index_assets_on_ai_generation_id"
    t.index ["project_id", "asset_type"], name: "index_assets_on_project_id_and_asset_type"
    t.index ["project_id"], name: "index_assets_on_project_id"
    t.index ["public_id"], name: "index_assets_on_public_id", unique: true
    t.index ["scene_id"], name: "index_assets_on_scene_id"
  end

  create_table "generation_jobs", force: :cascade do |t|
    t.jsonb "args", default: {}, null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "error", default: {}, null: false
    t.text "failure_reason"
    t.datetime "finished_at"
    t.string "idempotency_key", null: false
    t.integer "max_attempts", default: 3, null: false
    t.bigint "parent_job_id"
    t.integer "progress", default: 0, null: false
    t.bigint "project_id", null: false
    t.string "public_id", null: false
    t.string "queue", default: "default", null: false
    t.jsonb "result", default: {}, null: false
    t.bigint "scene_id"
    t.datetime "scheduled_at"
    t.string "sidekiq_jid"
    t.string "stage", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_generation_jobs_on_idempotency_key", unique: true
    t.index ["parent_job_id"], name: "index_generation_jobs_on_parent_job_id"
    t.index ["project_id", "stage"], name: "index_generation_jobs_on_project_id_and_stage"
    t.index ["project_id"], name: "index_generation_jobs_on_project_id"
    t.index ["public_id"], name: "index_generation_jobs_on_public_id", unique: true
    t.index ["scene_id"], name: "index_generation_jobs_on_scene_id"
    t.index ["status"], name: "index_generation_jobs_on_status"
  end

  create_table "generation_logs", force: :cascade do |t|
    t.bigint "ai_generation_id"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.bigint "generation_job_id"
    t.string "level", default: "info", null: false
    t.text "message", null: false
    t.bigint "project_id", null: false
    t.bigint "scene_id"
    t.string "stage"
    t.index ["ai_generation_id"], name: "index_generation_logs_on_ai_generation_id"
    t.index ["generation_job_id"], name: "index_generation_logs_on_generation_job_id"
    t.index ["level"], name: "index_generation_logs_on_level"
    t.index ["project_id", "created_at"], name: "index_generation_logs_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_generation_logs_on_project_id"
    t.index ["scene_id"], name: "index_generation_logs_on_scene_id"
  end

  create_table "jwt_denylists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "exp", null: false
    t.string "jti", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti", unique: true
  end

  create_table "music_tracks", force: :cascade do |t|
    t.bigint "asset_id"
    t.integer "bpm"
    t.datetime "created_at", null: false
    t.decimal "duration_seconds", precision: 9, scale: 3
    t.string "license"
    t.jsonb "metadata", default: {}, null: false
    t.string "mood"
    t.bigint "project_id"
    t.string "provider"
    t.string "public_id", null: false
    t.string "source_type", default: "licensed", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_music_tracks_on_asset_id"
    t.index ["project_id"], name: "index_music_tracks_on_project_id"
    t.index ["public_id"], name: "index_music_tracks_on_public_id", unique: true
  end

  create_table "preflight_reports", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.bigint "acknowledged_by_id"
    t.string "ai_disclosure", default: "review", null: false
    t.jsonb "checks", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "generated_by_generation_id"
    t.bigint "project_id", null: false
    t.string "public_id", null: false
    t.string "status", default: "review_required", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_render_id"
    t.jsonb "warnings", default: [], null: false
    t.index ["acknowledged_by_id"], name: "index_preflight_reports_on_acknowledged_by_id"
    t.index ["generated_by_generation_id"], name: "index_preflight_reports_on_generated_by_generation_id"
    t.index ["project_id", "created_at"], name: "index_preflight_reports_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_preflight_reports_on_project_id"
    t.index ["public_id"], name: "index_preflight_reports_on_public_id", unique: true
    t.index ["video_render_id"], name: "index_preflight_reports_on_video_render_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "aspect_ratio", default: "16:9", null: false
    t.string "audience"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "creator_instructions"
    t.jsonb "disclosure", default: {}, null: false
    t.string "failed_from_status"
    t.text "failure_reason"
    t.string "format", default: "youtube_long", null: false
    t.integer "image_seed"
    t.jsonb "metadata", default: {}, null: false
    t.string "niche"
    t.string "pipeline_checkpoint"
    t.string "pipeline_mode", default: "manual", null: false
    t.string "public_id", null: false
    t.boolean "research_enabled", default: false, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.integer "target_duration_seconds", default: 120, null: false
    t.bigint "template_id"
    t.bigint "template_version_id"
    t.string "title", default: "Untitled project", null: false
    t.string "tone"
    t.text "topic"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visual_style", default: "cinematic", null: false
    t.index ["created_at"], name: "index_projects_on_created_at"
    t.index ["public_id"], name: "index_projects_on_public_id", unique: true
    t.index ["template_id"], name: "index_projects_on_template_id"
    t.index ["template_version_id"], name: "index_projects_on_template_version_id"
    t.index ["user_id", "status"], name: "index_projects_on_user_id_and_status"
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "scenes", force: :cascade do |t|
    t.string "animation", default: "ken_burns", null: false
    t.decimal "background_music_level", precision: 4, scale: 2, default: "0.15", null: false
    t.text "caption"
    t.datetime "created_at", null: false
    t.decimal "duration_seconds", precision: 6, scale: 2, default: "5.0", null: false
    t.text "failure_reason"
    t.string "key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "narration"
    t.text "notes"
    t.integer "position", null: false
    t.bigint "project_id", null: false
    t.string "public_id", null: false
    t.bigint "script_id"
    t.bigint "selected_asset_id"
    t.string "status", default: "pending", null: false
    t.string "transition", default: "fade", null: false
    t.datetime "updated_at", null: false
    t.text "visual_prompt"
    t.string "visual_type", default: "image", null: false
    t.index ["project_id", "key"], name: "index_scenes_on_project_id_and_key", unique: true
    t.index ["project_id", "position"], name: "index_scenes_on_project_id_and_position", unique: true
    t.index ["project_id"], name: "index_scenes_on_project_id"
    t.index ["public_id"], name: "index_scenes_on_public_id", unique: true
    t.index ["script_id"], name: "index_scenes_on_script_id"
    t.index ["selected_asset_id"], name: "index_scenes_on_selected_asset_id"
  end

  create_table "scripts", force: :cascade do |t|
    t.bigint "ai_generation_id"
    t.jsonb "claims", default: [], null: false
    t.datetime "created_at", null: false
    t.text "creative_notes"
    t.boolean "current", default: true, null: false
    t.integer "estimated_duration_seconds"
    t.text "full_narration"
    t.text "hook"
    t.bigint "project_id", null: false
    t.string "public_id", null: false
    t.jsonb "sections", default: [], null: false
    t.string "selected_title"
    t.string "source_type", default: "ai_generated", null: false
    t.text "story_angle"
    t.jsonb "title_options", default: [], null: false
    t.string "tone"
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["ai_generation_id"], name: "index_scripts_on_ai_generation_id"
    t.index ["project_id", "current"], name: "index_scripts_on_project_id_and_current", unique: true, where: "current"
    t.index ["project_id", "version"], name: "index_scripts_on_project_id_and_version", unique: true
    t.index ["project_id"], name: "index_scripts_on_project_id"
    t.index ["public_id"], name: "index_scripts_on_public_id", unique: true
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "accessed_at"
    t.datetime "created_at", null: false
    t.jsonb "extracted_claims", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "project_id", null: false
    t.string "provided_by", default: "user", null: false
    t.string "public_id", null: false
    t.date "published_on"
    t.string "publisher"
    t.text "raw_excerpt"
    t.string "reliability", default: "unknown", null: false
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["project_id"], name: "index_sources_on_project_id"
    t.index ["public_id"], name: "index_sources_on_public_id", unique: true
  end

  create_table "template_versions", force: :cascade do |t|
    t.text "changelog"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "public_id", null: false
    t.datetime "published_at"
    t.bigint "template_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["public_id"], name: "index_template_versions_on_public_id", unique: true
    t.index ["template_id", "version"], name: "index_template_versions_on_template_id_and_version", unique: true
    t.index ["template_id"], name: "index_template_versions_on_template_id"
  end

  create_table "templates", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "latest_version_id"
    t.string "name", null: false
    t.bigint "owner_id"
    t.bigint "preview_asset_id"
    t.string "public_id", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["latest_version_id"], name: "index_templates_on_latest_version_id"
    t.index ["owner_id"], name: "index_templates_on_owner_id"
    t.index ["public_id"], name: "index_templates_on_public_id", unique: true
    t.index ["slug"], name: "index_templates_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", default: "", null: false
    t.string "public_id", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "video_renders", force: :cascade do |t|
    t.decimal "cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "duration_seconds", precision: 9, scale: 3
    t.jsonb "error", default: {}, null: false
    t.text "failure_reason"
    t.datetime "finished_at"
    t.integer "fps"
    t.integer "frame_count"
    t.integer "height"
    t.text "log"
    t.jsonb "manifest", default: {}, null: false
    t.bigint "output_asset_id"
    t.integer "progress", default: 0, null: false
    t.bigint "project_id", null: false
    t.string "public_id", null: false
    t.decimal "render_seconds", precision: 10, scale: 3
    t.string "renderer", default: "remotion", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.bigint "template_version_id"
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.integer "width"
    t.index ["output_asset_id"], name: "index_video_renders_on_output_asset_id"
    t.index ["project_id", "version"], name: "index_video_renders_on_project_id_and_version", unique: true
    t.index ["project_id"], name: "index_video_renders_on_project_id"
    t.index ["public_id"], name: "index_video_renders_on_public_id", unique: true
    t.index ["template_version_id"], name: "index_video_renders_on_template_version_id"
  end

  create_table "voice_generations", force: :cascade do |t|
    t.bigint "ai_generation_id"
    t.jsonb "alignment", default: {}, null: false
    t.bigint "audio_asset_id"
    t.jsonb "captions", default: [], null: false
    t.decimal "cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "duration_seconds", precision: 9, scale: 3
    t.text "failure_reason"
    t.string "model"
    t.bigint "project_id", null: false
    t.string "provider", default: "elevenlabs", null: false
    t.string "provider_request_id"
    t.string "public_id", null: false
    t.bigint "scene_id"
    t.bigint "script_id"
    t.string "status", default: "pending", null: false
    t.text "text"
    t.datetime "updated_at", null: false
    t.string "voice_id"
    t.string "voice_name"
    t.index ["ai_generation_id"], name: "index_voice_generations_on_ai_generation_id"
    t.index ["audio_asset_id"], name: "index_voice_generations_on_audio_asset_id"
    t.index ["project_id"], name: "index_voice_generations_on_project_id"
    t.index ["public_id"], name: "index_voice_generations_on_public_id", unique: true
    t.index ["scene_id"], name: "index_voice_generations_on_scene_id"
    t.index ["script_id"], name: "index_voice_generations_on_script_id"
  end

  add_foreign_key "ai_generations", "projects"
  add_foreign_key "ai_generations", "scenes"
  add_foreign_key "assets", "ai_generations", on_delete: :nullify
  add_foreign_key "assets", "projects"
  add_foreign_key "assets", "scenes"
  add_foreign_key "generation_jobs", "generation_jobs", column: "parent_job_id"
  add_foreign_key "generation_jobs", "projects"
  add_foreign_key "generation_jobs", "scenes"
  add_foreign_key "generation_logs", "ai_generations", on_delete: :nullify
  add_foreign_key "generation_logs", "generation_jobs", on_delete: :nullify
  add_foreign_key "generation_logs", "projects"
  add_foreign_key "generation_logs", "scenes", on_delete: :nullify
  add_foreign_key "music_tracks", "assets", on_delete: :nullify
  add_foreign_key "music_tracks", "projects"
  add_foreign_key "preflight_reports", "ai_generations", column: "generated_by_generation_id", on_delete: :nullify
  add_foreign_key "preflight_reports", "projects"
  add_foreign_key "preflight_reports", "users", column: "acknowledged_by_id"
  add_foreign_key "preflight_reports", "video_renders", on_delete: :nullify
  add_foreign_key "projects", "template_versions", on_delete: :nullify
  add_foreign_key "projects", "templates"
  add_foreign_key "projects", "users"
  add_foreign_key "scenes", "assets", column: "selected_asset_id", on_delete: :nullify
  add_foreign_key "scenes", "projects"
  add_foreign_key "scenes", "scripts"
  add_foreign_key "scripts", "ai_generations", on_delete: :nullify
  add_foreign_key "scripts", "projects"
  add_foreign_key "sources", "projects"
  add_foreign_key "template_versions", "templates"
  add_foreign_key "templates", "assets", column: "preview_asset_id", on_delete: :nullify
  add_foreign_key "templates", "template_versions", column: "latest_version_id", on_delete: :nullify
  add_foreign_key "templates", "users", column: "owner_id"
  add_foreign_key "video_renders", "assets", column: "output_asset_id", on_delete: :nullify
  add_foreign_key "video_renders", "projects"
  add_foreign_key "video_renders", "template_versions"
  add_foreign_key "voice_generations", "ai_generations", on_delete: :nullify
  add_foreign_key "voice_generations", "assets", column: "audio_asset_id", on_delete: :nullify
  add_foreign_key "voice_generations", "projects"
  add_foreign_key "voice_generations", "scenes"
  add_foreign_key "voice_generations", "scripts"
end
