import { z } from "zod";

/**
 * The Scene JSON contract (spec §19) — the interchange shape between AI planning
 * (Rails) and rendering (Remotion). Keep this in lockstep with
 * `Scene#to_scene_json` in apps/api.
 */

export const VISUAL_TYPES = [
  "image",
  "generated_video",
  "animated_diagram",
  "chart",
  "timeline",
  "map",
  "quote_card",
  "text_animation",
  "screen_recording",
  "split_screen",
] as const;

export const ANIMATIONS = ["ken_burns", "pan", "scale", "text_reveal", "none"] as const;

/**
 * Phase 1 Task 4 — Director Direction Layer. This is the single typed
 * catalog of render capabilities the Director (the planner) may choose
 * from; the Rails-side planner services validate their LLM's choices
 * against a mirrored Ruby copy of these same value lists (see
 * `Scene::TRANSITIONS` / `Scene::CAMERA_MOTIONS` / etc in apps/api) before
 * ever writing them, so an invalid choice never reaches this schema. "fade"
 * is kept only so scenes written before this task (which always got
 * "fade" as the default) still parse — the renderer treats it exactly like
 * "crossfade". "map" and "split_screen" remain valid VISUAL_TYPES for the
 * same backward-compatibility reason (old rows), even though the planner
 * is no longer instructed to choose them (§ Task 4 Part B).
 */
export const TRANSITIONS = [
  "cut", "fade", "crossfade", "fade_from_black", "slide", "wipe", "zoom",
] as const;

export const CAMERA_MOTIONS = [
  "static", "slow_push_in", "push_in", "pull_out", "pan_left", "pan_right",
  "tilt_up", "drift", "dramatic_zoom",
] as const;
export const CAMERA_INTENSITIES = ["low", "medium", "high"] as const;

export const OVERLAY_TYPES = [
  "none", "keyword_highlight", "lower_third", "stat_callout", "title_card",
] as const;

export const TEXT_STYLES = [
  "stagger_reveal", "punch_in", "big_number", "quote", "list_reveal", "timeline",
] as const;

export const SHOT_TYPES = [
  "wide", "establishing", "medium", "close_up", "tracking", "push_in",
  "pull_out", "pan", "tilt", "top_down", "static", "screen", "chart",
] as const;

/** An image unit's optional on-image decoration (Task 4 Part A). Never
 *  present on a "text" unit — text units express everything via TextSpec. */
export const OverlaySchema = z.object({
  type: z.enum(OVERLAY_TYPES).default("none"),
  /** The word/phrase to highlight, or the callout/lower-third text. */
  text: z.string().nullable().default(null),
  /** stat_callout only: the big number/stat itself, shown above `text`. */
  value: z.string().nullable().default(null),
});
export type Overlay = z.infer<typeof OverlaySchema>;

/** A "text" unit's structured kinetic-typography spec (Task 2 originally;
 *  extended Task 4 with the style catalog + list_reveal/timeline/big_number
 *  payloads). Superset of every field any TextAnimationScene style reads —
 *  each style ignores the fields it doesn't need. Still fully optional so a
 *  bare `{}` (or the pre-Task-4 shape) renders exactly as it always has. */
export const TextSpecSchema = z.object({
  lines: z.array(z.string()).optional(),
  keywords: z.array(z.string()).optional(),
  emphasis: z.array(z.string()).optional(),
  style: z.string().nullable().optional(),
  animation_style: z.string().nullable().optional(),
  duration: z.number().optional(),
  /** Which TextAnimationScene renderer to use. Defaults to the original
   *  (and still only pre-Task-4) style when absent. */
  text_style: z.enum(TEXT_STYLES).default("stagger_reveal"),
  /** list_reveal (place names, items) / timeline (dated steps) payload. */
  items: z.array(z.string()).optional(),
  /** big_number payload: the counted-up figure and its unit/suffix. */
  number: z.union([z.number(), z.string()]).nullable().optional(),
  unit: z.string().nullable().optional(),
});
export type TextSpec = z.infer<typeof TextSpecSchema>;

/**
 * One camera shot inside a scene (planning-doc §6/§7). A scene with `shots`
 * plays them in sequence; a scene with none renders scene-level as before.
 */
export const ShotSchema = z.object({
  id: z.string(),
  duration: z.number().positive().max(120),
  shot_type: z.string().default("static"),
  camera_movement: z.string().nullable().default(null),
  framing: z.string().nullable().default(null),
  action: z.string().nullable().default(null),
  visual_type: z.enum(VISUAL_TYPES).default("image"),
  asset_id: z.string().nullable().default(null),
  motion: z.record(z.unknown()).default({}),
  /** Which Media::ProductionDispatcher-routed service produced this shot's
   *  visual (Phase 1 Task 2) — null until produced. */
  production_method: z.string().nullable().default(null),
  /** Structured kinetic-typography spec when production_method is "text". */
  text_spec: TextSpecSchema.nullable().default(null),
  /** Optional on-image decoration (Task 4) — image units only. */
  overlay: OverlaySchema.nullable().default(null),
  /** Why the Director chose this shot's camera/overlay (Task 4+) — for the
   *  Task 3 "Direct" panel's "Why" line; the renderer itself ignores it,
   *  same as `action`/`framing` above already were before this. */
  direction_reason: z.string().nullable().default(null),
});
export type Shot = z.infer<typeof ShotSchema>;

export const SceneSchema = z.object({
  /** Stable scene key, e.g. "scene_01". */
  id: z.string().regex(/^scene_\d{2,}$/),
  /** Seconds on screen. */
  duration: z.number().positive().max(120),
  narration: z.string().nullable().default(null),
  visual_type: z.enum(VISUAL_TYPES),
  visual_prompt: z.string().nullable().default(null),
  /** Public id of the resolved asset, or null until one is generated/selected. */
  asset_id: z.string().nullable().default(null),
  caption: z.string().nullable().default(null),
  animation: z.enum(ANIMATIONS).default("ken_burns"),
  transition: z.enum(TRANSITIONS).default("fade"),
  /** 0..1 music bed level under this scene. */
  background_music_level: z.number().min(0).max(1).default(0.15),

  // --- Production direction (planning-doc §6). All optional / defaulted so old
  // manifests still parse and old scenes render unchanged. ---
  purpose: z.string().nullable().default(null),
  content_type: z.string().nullable().default(null),
  action: z.string().nullable().default(null),
  camera: z.record(z.unknown()).nullable().default(null),
  motion: z.record(z.unknown()).nullable().default(null),
  mood: z.string().nullable().default(null),
  asset_strategy: z.string().default("image"),
  negative_prompt: z.string().nullable().default(null),
  shots: z.array(ShotSchema).default([]),
  /** Which Media::ProductionDispatcher-routed service produced this scene's
   *  visual (Phase 1 Task 2) — null until produced. */
  production_method: z.string().nullable().default(null),
  /** Structured kinetic-typography spec when production_method is "text". */
  text_spec: TextSpecSchema.nullable().default(null),
  /** Optional on-image decoration (Task 4) — image units only. */
  overlay: OverlaySchema.nullable().default(null),
  /** Why the Director chose this scene's asset_strategy/visual_type
   *  (scene_planner v2+, Task 2.2) — for the Task 3 "Direct" panel. */
  visual_reason: z.string().nullable().default(null),
  /** Why the Director chose this scene's camera/transition/overlay/
   *  text_style (Task 4+) — for the Task 3 "Direct" panel's "Why" line. */
  direction_reason: z.string().nullable().default(null),
});

export type Scene = z.infer<typeof SceneSchema>;

export const StoryboardSchema = z.object({
  project_id: z.string(),
  aspect_ratio: z.enum(["16:9", "9:16", "1:1"]),
  scenes: z.array(SceneSchema).min(1),
});

export type Storyboard = z.infer<typeof StoryboardSchema>;

/**
 * The render manifest (spec §20 step 14) — a fully-resolved storyboard plus the
 * template config and audio tracks the renderer needs. Asset references are
 * resolved to signed URLs at manifest-build time.
 */
export const RenderAssetSchema = z.object({
  id: z.string(),
  type: z.enum(["image", "video", "audio", "music"]),
  url: z.string().url(),
  width: z.number().int().optional(),
  height: z.number().int().optional(),
  duration: z.number().optional(),
});

export const CaptionCueSchema = z.object({
  text: z.string(),
  start: z.number(),
  end: z.number(),
});
export type CaptionCue = z.infer<typeof CaptionCueSchema>;

export const RenderSceneSchema = SceneSchema.extend({
  /** Per-scene narration audio, resolved to an absolute URL. */
  narration_audio_url: z.string().url().nullable().default(null),
  /** Character/word alignment for caption timing (spec §26). */
  alignment: z.record(z.unknown()).nullable().default(null),
  /** Timed caption cues (seconds, relative to the scene start). */
  captions: z.array(CaptionCueSchema).default([]),
});
export type RenderScene = z.infer<typeof RenderSceneSchema>;

export const RenderManifestSchema = z.object({
  render_id: z.string(),
  project_id: z.string(),
  width: z.number().int(),
  height: z.number().int(),
  fps: z.number().int().default(30),
  template: z.record(z.unknown()),
  scenes: z.array(RenderSceneSchema),
  assets: z.array(RenderAssetSchema),
  /** Task 6.2 Part 2: the project look's grade. "clean" (default) applies no
   *  grain, vignette or tone wash; "film" keeps the original film grade. */
  look: z.object({ grade: z.enum([ "clean", "film" ]).default("clean") }).nullable().default(null),
  music: z
    .object({
      url: z.string().url(),
      level: z.number().min(0).max(1).default(0.12),
    })
    .nullable()
    .default(null),
});

export type RenderManifest = z.infer<typeof RenderManifestSchema>;

export function parseScene(input: unknown): Scene {
  return SceneSchema.parse(input);
}

export function parseRenderManifest(input: unknown): RenderManifest {
  return RenderManifestSchema.parse(input);
}
