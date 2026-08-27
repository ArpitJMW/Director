/**
 * Shared API types for Clipify. These mirror the Rails serializers in
 * `apps/api/app/serializers` and the documented API in `docs/api.md`.
 */

import type { Scene as SceneContract } from "@clipify/video-schema";

export type ProjectStatus =
  | "draft"
  | "researching"
  | "script_generating"
  | "storyboarding"
  | "generating_assets"
  | "generating_voice"
  | "generating_captions"
  | "rendering"
  | "quality_check"
  | "completed"
  | "failed"
  | "cancelled";

export type ProjectFormat = "youtube_long" | "youtube_short" | "reel";
export type AspectRatio = "16:9" | "9:16" | "1:1";

export interface User {
  id: string;
  name: string;
  email: string;
  created_at: string;
}

export interface Project {
  id: string;
  title: string;
  topic: string | null;
  status: ProjectStatus;
  format: ProjectFormat;
  aspect_ratio: AspectRatio;
  niche: string | null;
  audience: string | null;
  tone: string | null;
  target_duration_seconds: number;
  creator_instructions: string | null;
  research_enabled: boolean;
  failure_reason: string | null;
  settings: Record<string, unknown>;
  disclosure: Record<string, unknown>;
  template_id: string | null;
  scene_count: number;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
  current_script?: Script | null;
  scenes?: SceneResource[];
}

export interface Script {
  id: string;
  version: number;
  current: boolean;
  selected_title: string | null;
  title_options: string[];
  hook: string | null;
  story_angle: string | null;
  sections: unknown[];
  full_narration: string | null;
  estimated_duration_seconds: number | null;
  creative_notes: string | null;
  source_type: "ai_generated" | "user_provided" | "ai_edited";
  claims: unknown[];
  created_at: string;
  updated_at: string;
}

export interface SceneResource {
  id: string;
  project_id: string;
  status: "pending" | "generating_prompt" | "generating_asset" | "ready" | "failed";
  position: number;
  notes: string | null;
  failure_reason: string | null;
  scene: SceneContract;
  selected_asset: AssetResource | null;
  created_at: string;
  updated_at: string;
}

export interface AssetResource {
  id: string;
  asset_type: "image" | "video" | "audio" | "music" | "logo" | "caption_file" | "thumbnail";
  url: string | null;
  content_type: string | null;
  width: number | null;
  height: number | null;
  duration_seconds: number | null;
  provider: string | null;
  model: string | null;
  prompt: string | null;
  cost_usd: number;
  source_type: string;
  license: string | null;
  ai_generated: boolean;
  realistic: boolean;
  represents_real_person: boolean;
  represents_real_event_or_place: boolean;
  requires_disclosure: boolean;
  scene_id: string | null;
  created_at: string;
}

export interface TemplateVersion {
  id: string;
  version: number;
  config: Record<string, unknown>;
  changelog: string | null;
  published_at: string | null;
}

export interface Template {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  category: string | null;
  status: "draft" | "published" | "archived";
  built_in: boolean;
  preview_url: string | null;
  latest_version: TemplateVersion | null;
  created_at: string;
}

export interface VideoRender {
  id: string;
  version: number;
  status: "queued" | "rendering" | "uploading" | "completed" | "failed" | "cancelled";
  renderer: string;
  progress: number;
  width: number | null;
  height: number | null;
  fps: number | null;
  duration_seconds: number | null;
  output_url: string | null;
  render_seconds: number | null;
  cost_usd: number;
  failure_reason: string | null;
  started_at: string | null;
  finished_at: string | null;
  created_at: string;
}

export interface PreflightReport {
  id: string;
  status: "ready" | "review_required";
  checks: Record<string, "pass" | "warn" | "review">;
  ai_disclosure: "required" | "not_required" | "review";
  warnings: unknown[];
  acknowledged_at: string | null;
  acknowledged_by: string | null;
  video_render_id: string | null;
  created_at: string;
  disclaimer: string;
}

// --- Request payloads -------------------------------------------------------

export interface CreateProjectInput {
  title: string;
  topic?: string;
  format?: ProjectFormat;
  aspect_ratio?: AspectRatio;
  niche?: string;
  audience?: string;
  tone?: string;
  target_duration_seconds?: number;
  creator_instructions?: string;
  research_enabled?: boolean;
  template_id?: string | null;
  settings?: Record<string, unknown>;
}

export type UpdateProjectInput = Partial<CreateProjectInput>;

export interface UpdateSceneInput {
  narration?: string;
  visual_type?: SceneContract["visual_type"];
  visual_prompt?: string;
  caption?: string;
  animation?: SceneContract["animation"];
  transition?: SceneContract["transition"];
  duration_seconds?: number;
  background_music_level?: number;
  notes?: string;
}

// --- API envelope ----------------------------------------------------------

export interface ApiError {
  error: string;
  message?: string;
  messages?: string[];
  available_in?: string;
}
