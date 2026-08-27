import { z } from "zod";
import { RenderManifestSchema } from "@clipify/video-schema";

export { RenderManifestSchema };
export type RenderManifest = z.infer<typeof RenderManifestSchema>;

export const COMPOSITION_ID = "ClipifyVideo";

/** A neutral default manifest so the Remotion studio can open without props. */
export const defaultManifest: RenderManifest = {
  render_id: "preview",
  project_id: "preview",
  width: 1920,
  height: 1080,
  fps: 30,
  template: {},
  scenes: [
    {
      id: "scene_01",
      duration: 4,
      narration: "This is a preview scene.",
      visual_type: "text_animation",
      visual_prompt: null,
      asset_id: null,
      caption: "Preview",
      animation: "ken_burns",
      transition: "fade",
      background_music_level: 0.15,
      narration_audio_url: null,
      alignment: null,
      captions: [{ text: "Preview", start: 0, end: 4 }],
    },
  ],
  assets: [],
  music: null,
};
