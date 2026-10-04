/**
 * Shared API types for Clipify. These mirror the Rails serializers in
 * `apps/api/app/serializers` and the documented API in `docs/api.md`.
 */

import type {
  CAMERA_INTENSITIES,
  CAMERA_MOTIONS,
  OVERLAY_TYPES,
  Overlay,
  Scene as SceneContract,
  Shot as ShotContract,
  TEXT_STYLES,
  TRANSITIONS,
} from "@clipify/video-schema";

export type { Overlay, TextSpec, Scene as SceneContract, Shot as ShotContract } from "@clipify/video-schema";
export {
  CAMERA_INTENSITIES,
  CAMERA_MOTIONS,
  OVERLAY_TYPES,
  TEXT_STYLES,
  TRANSITIONS,
} from "@clipify/video-schema";

/**
 * Phase 1 Task 3 — the Director's per-unit choices, as the web app EDITS
 * them. Read state for an existing unit comes back on `SceneContract`/
 * `ShotContract` itself (camera/motion/transition/overlay/text_spec, from
 * Task 4); this is the shape a PATCH body's `direction` key takes to change
 * any of it. Every value must be a catalog member from packages/video-schema
 * — the web app never hand-writes its own option list, and the API rejects
 * (422) anything not in the same catalog.
 */
export interface DirectionInput {
  camera_motion?: (typeof CAMERA_MOTIONS)[number];
  camera_intensity?: (typeof CAMERA_INTENSITIES)[number];
  /** Scene-level only — how this scene transitions in from the previous one. */
  transition_in?: (typeof TRANSITIONS)[number];
  /** Image units only. `{ type: "none" }` (or omitting overlay) clears it. */
  overlay?: { type: (typeof OVERLAY_TYPES)[number]; text?: string | null; value?: string | null } | null;
  /** Text units only. */
  text_style?: (typeof TEXT_STYLES)[number];
  items?: string[];
  number?: number | string | null;
  unit?: string | null;
}

/** One shot's editable fields (Phase 1 Task 3) — camera/overlay direction
 *  only; a shot has no transition_in or text_style of its own (see the Task
 *  4.2 shot_planner prompt: transitions/text are scene-level decisions). */
export interface UpdateShotInput {
  id: string;
  direction?: Omit<DirectionInput, "transition_in" | "text_style" | "items" | "number" | "unit">;
}

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
export type VisualStyle =
  | "cinematic"
  | "photorealistic"
  | "wildlife_documentary"
  | "documentary"
  | "3d_animation"
  | "illustration"
  | "anime"
  | "watercolor";
export type AspectRatio = "16:9" | "9:16" | "1:1";

export interface User {
  id: string;
  name: string;
  email: string;
  created_at: string;
}

export type PipelineCheckpoint = "storyboard" | "review";

export interface PipelineState {
  mode: "auto" | "manual";
  checkpoint: PipelineCheckpoint | null;
  active_stage: GenerationStage | null;
}

export interface Project {
  id: string;
  title: string;
  topic: string | null;
  status: ProjectStatus;
  pipeline: PipelineState;
  format: ProjectFormat;
  visual_style: VisualStyle;
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
  /** True when any scene/shot has a direction-only edit (Phase 1 Task 3)
   *  made after the project's last completed render. */
  pending_render_changes: boolean;
  /** Task 6: project-level QA roll-up (single-project responses only). */
  qa?: {
    checked: boolean;
    setting: boolean;
    units?: number;
    passed?: number;
    failed?: number;
    unavailable?: number;
    repaired?: number;
    issues?: number;
  };
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

export interface CaptionCue {
  text: string;
  start: number;
  end: number;
}

/** Task 6: one unit's AI-QA result, rolled up from the scene and its shots. */
export interface SceneQa {
  status: "passed" | "failed" | "unavailable";
  issues: { issue_type: string; severity: "low" | "medium" | "high" | "info"; evidence: string; source: string }[];
  repaired: boolean;
  repair_outcome: "repaired" | "failed" | "skipped_unit_limit" | "skipped_project_limit" | null;
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
  narration_audio: {
    url: string | null;
    duration_seconds: number | null;
    provider: string;
  } | null;
  captions: CaptionCue[];
  /** Task 6: AI-QA result for this scene (null until the quality_check stage ran). */
  qa: SceneQa | null;
  /** True once this scene's asset_strategy/visual_prompt/etc changed enough
   *  that the current asset (if any) no longer matches — needs the pipeline
   *  to (re)generate it. A brand-new, never-generated scene is also true. */
  needs_regeneration: boolean;
  /** True when a direction-only edit (camera/transition/overlay/text_style)
   *  happened after the project's last completed render — the existing
   *  asset is still valid, but the video needs re-rendering to show it. */
  needs_rerender: boolean;
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

export type CheckVerdict = "pass" | "warn" | "review";

export interface PreflightWarning {
  check: string;
  message: string;
}

export interface PreflightReport {
  id: string;
  status: "ready" | "review_required";
  checks: Record<string, CheckVerdict>;
  ai_disclosure: "required" | "not_required" | "review";
  warnings: PreflightWarning[];
  acknowledged_at: string | null;
  acknowledged_by: string | null;
  video_render_id: string | null;
  created_at: string;
  disclaimer: string;
}

export type GenerationStage =
  | "validate"
  | "research"
  | "collect_sources"
  | "story_angle"
  | "script"
  | "fact_check"
  | "storyboard"
  | "visual_direction"
  | "prompts"
  | "assets"
  | "voice"
  | "narration"
  | "captions"
  | "music"
  | "manifest"
  | "render"
  | "quality_check"
  | "preflight"
  | "finalize";

export interface GenerationJob {
  id: string;
  stage: GenerationStage;
  status: "pending" | "queued" | "running" | "succeeded" | "failed" | "cancelled" | "retrying";
  progress: number;
  attempts: number;
  max_attempts: number;
  active: boolean;
  result: Record<string, unknown>;
  failure_reason: string | null;
  scene_id: string | null;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
}

// --- Request payloads -------------------------------------------------------

export interface CreateProjectInput {
  title: string;
  topic?: string;
  format?: ProjectFormat;
  visual_style?: VisualStyle;
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
  /** @deprecated prefer `direction.transition_in` — kept because the API
   *  still accepts either; `direction.transition_in` wins if both are sent. */
  transition?: SceneContract["transition"];
  duration_seconds?: number;
  background_music_level?: number;
  notes?: string;
  // --- Phase 1 Task 3 additions ---
  /** "image" | "text" — the only two the studio can actually produce.
   *  Changing this flags the scene (and its shots) for regeneration. */
  asset_strategy?: "image" | "text";
  purpose?: string;
  action?: string;
  mood?: string;
  /** Direction-only edit — never triggers regeneration, only a re-render. */
  direction?: DirectionInput;
  /** Per-shot direction edits, nested under the scene update (Phase 1 Task 3
   *  Step 2 — smallest reasonable extension; see the Task 3 report for why
   *  this wasn't given its own shots#update route). */
  shots?: UpdateShotInput[];
}

// --- API envelope ----------------------------------------------------------

export interface ApiError {
  error: string;
  message?: string;
  messages?: string[];
  available_in?: string;
}
