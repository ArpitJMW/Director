import { describe, expect, it } from "vitest";
import {
  CAMERA_INTENSITIES,
  CAMERA_MOTIONS,
  OVERLAY_TYPES,
  OverlaySchema,
  parseScene,
  SceneSchema,
  ShotSchema,
  TEXT_STYLES,
  TextSpecSchema,
  TRANSITIONS,
} from "./index.js";

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

describe("Direction catalog (Phase 1 Task 4)", () => {
  it("keeps the legacy transition values valid alongside the new ones", () => {
    expect(TRANSITIONS).toContain("fade"); // pre-Task-4 default, still parses
    for (const t of ["cut", "crossfade", "fade_from_black", "slide", "wipe", "zoom"] as const) {
      expect(TRANSITIONS).toContain(t);
    }
    expect(SceneSchema.safeParse({ id: "scene_01", duration: 5, visual_type: "image", transition: "wipe" }).success).toBe(true);
    expect(SceneSchema.safeParse({ id: "scene_01", duration: 5, visual_type: "image", transition: "bogus" }).success).toBe(false);
  });

  it("exposes the full camera_motion and intensity catalog", () => {
    expect(CAMERA_MOTIONS).toEqual([
      "static", "slow_push_in", "push_in", "pull_out", "pan_left", "pan_right",
      "tilt_up", "drift", "dramatic_zoom",
    ]);
    expect(CAMERA_INTENSITIES).toEqual(["low", "medium", "high"]);
  });

  it("OverlaySchema accepts every catalog type and rejects an unknown one", () => {
    for (const type of OVERLAY_TYPES) {
      expect(OverlaySchema.safeParse({ type }).success).toBe(true);
    }
    expect(OverlaySchema.safeParse({ type: "confetti" }).success).toBe(false);
    // Backward compatible: a scene/shot with no overlay at all still parses.
    expect(SceneSchema.parse({ id: "scene_01", duration: 5, visual_type: "image" }).overlay).toBeNull();
  });

  it("TextSpecSchema defaults text_style to stagger_reveal and accepts list_reveal/timeline/big_number payloads", () => {
    expect(TEXT_STYLES).toEqual(["stagger_reveal", "punch_in", "big_number", "quote", "list_reveal", "timeline"]);

    const bare = TextSpecSchema.parse({});
    expect(bare.text_style).toBe("stagger_reveal");

    const list = TextSpecSchema.parse({ text_style: "list_reveal", items: ["Venice", "Paris", "Mainz"] });
    expect(list.items).toEqual(["Venice", "Paris", "Mainz"]);

    const timeline = TextSpecSchema.parse({ text_style: "timeline", items: ["1450: Movable type", "1814: Steam power"] });
    expect(timeline.text_style).toBe("timeline");

    const bigNumber = TextSpecSchema.parse({ text_style: "big_number", number: 42, unit: "%" });
    expect(bigNumber.number).toBe(42);
    expect(bigNumber.unit).toBe("%");

    expect(TextSpecSchema.safeParse({ text_style: "not_a_style" }).success).toBe(false);
  });

  it("a pre-Task-4 text_spec shape (lines/keywords/emphasis only) still parses", () => {
    const legacy = TextSpecSchema.parse({
      lines: ["Hello world"], keywords: [ "hello" ], emphasis: [ "hello" ],
      style: "kinetic_typography", animation_style: "text_reveal", duration: 5,
    });
    expect(legacy.text_style).toBe("stagger_reveal");
    expect(legacy.lines).toEqual(["Hello world"]);
  });

  it("Shot and Scene both carry the optional overlay/text_spec fields", () => {
    const shot = ShotSchema.parse({ id: "scene_01_shot_1", duration: 3, overlay: { type: "stat_callout", value: "42%", text: "of failures" } });
    expect(shot.overlay?.type).toBe("stat_callout");
  });
});
