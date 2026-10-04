import { z } from "zod";
import { RenderManifestSchema } from "@clipify/video-schema";

export { RenderManifestSchema };
export type RenderManifest = z.infer<typeof RenderManifestSchema>;

export const COMPOSITION_ID = "ClipifyVideo";

/** A neutral default manifest so the Remotion studio can open without props.
 *  Parsed through the schema so every defaulted field is filled in. */
export const defaultManifest: RenderManifest = RenderManifestSchema.parse({
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
      caption: "Preview",
      captions: [{ text: "Preview", start: 0, end: 4 }],
    },
  ],
  assets: [],
  music: null,
});
