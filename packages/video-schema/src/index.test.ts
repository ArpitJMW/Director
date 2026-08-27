import { describe, expect, it } from "vitest";
import { parseScene, SceneSchema } from "./index.js";

describe("SceneSchema", () => {
  it("accepts the canonical scene shape from spec §19", () => {
    const scene = parseScene({
      id: "scene_01",
      duration: 7,
      narration: "...",
      visual_type: "image",
      visual_prompt: "...",
      asset_id: null,
      caption: "...",
      animation: "ken_burns",
      transition: "fade",
      background_music_level: 0.15,
    });
    expect(scene.id).toBe("scene_01");
  });

  it("applies defaults for optional fields", () => {
    const scene = parseScene({ id: "scene_02", duration: 5, visual_type: "chart" });
    expect(scene.animation).toBe("ken_burns");
    expect(scene.background_music_level).toBe(0.15);
    expect(scene.asset_id).toBeNull();
  });

  it("rejects an unknown visual_type and a bad id", () => {
    expect(SceneSchema.safeParse({ id: "scene_01", duration: 5, visual_type: "hologram" }).success).toBe(false);
    expect(SceneSchema.safeParse({ id: "01", duration: 5, visual_type: "image" }).success).toBe(false);
  });
});
