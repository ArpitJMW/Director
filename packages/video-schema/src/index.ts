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
export const TRANSITIONS = ["fade", "slide", "zoom", "cut"] as const;

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

export const RenderManifestSchema = z.object({
  render_id: z.string(),
  project_id: z.string(),
  width: z.number().int(),
  height: z.number().int(),
  fps: z.number().int().default(30),
  template: z.record(z.unknown()),
  scenes: z.array(
    SceneSchema.extend({
      /** Per-scene narration audio, resolved. */
      narration_audio_url: z.string().url().nullable().default(null),
      /** ElevenLabs-style character/word alignment for caption timing (spec §26). */
      alignment: z.record(z.unknown()).nullable().default(null),
    }),
  ),
  assets: z.array(RenderAssetSchema),
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
