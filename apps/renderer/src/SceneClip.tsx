import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  Series,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import type { RenderManifest, RenderScene, Shot } from "@clipify/video-schema";
import { Grade } from "./Grade";
import { Overlay } from "./Overlay";
import { TextAnimationScene } from "./TextAnimationScene";

/** Gentle in-camera-ish contrast/saturation pop for generated stills. */
const IMAGE_FILTER = "contrast(1.06) saturate(1.05) brightness(0.98)";

type Assets = RenderManifest["assets"];
type Template = RenderManifest["template"];

type Props = {
  scene: RenderScene;
  /** Position of this scene in the storyboard — drives motion variety. */
  index: number;
  assets: Assets;
  template: Template;
  /** Frames this scene's OUTGOING transition borrows from its own tail
   *  (Task 4 — see ClipifyVideo.tsx's transitionFramesFor). The outer
   *  <TransitionSeries.Sequence> wrapping this scene is already padded by
   *  this amount so the crossfade has something to overlap with the next
   *  scene; a scene with shots needs to know the same number so its LAST
   *  shot's own bounding Sequence can be stretched to match — otherwise the
   *  shot list runs out at the scene's natural length and the padded tail
   *  renders nothing at all (Task 4.3 Part 2's root cause). */
  outgoingTransitionFrames?: number;
  /** Task 6.2 Part 2: the project look's grade ("clean" unless the look asks for film). */
  grade?: "clean" | "film";
};

/**
 * Ken Burns moves, each a (start → end) of scale + translate (% of element).
 * Consecutive units cycle through them so nothing reads as static. Translate
 * stays inside the overflow `scale` buys, so edges never show with cover fit.
 * Indices 0-5 are unchanged from before Phase 1 Task 4 (existing shot_type
 * hints below still resolve to the same moves they always did); 6-7 are new,
 * backing the richer `camera_motion` catalog's "drift" and "dramatic_zoom".
 */
const MOVES: { scale: [number, number]; x: [number, number]; y: [number, number] }[] = [
  { scale: [1.04, 1.20], x: [0, 0], y: [0, 0] }, // 0 slow push in
  { scale: [1.22, 1.05], x: [0, 0], y: [0, 0] }, // 1 slow pull out / pull out
  { scale: [1.16, 1.16], x: [4, -4], y: [0, 0] }, // 2 pan left
  { scale: [1.16, 1.16], x: [-4, 4], y: [0, 0] }, // 3 pan right
  { scale: [1.10, 1.19], x: [-3, 2], y: [3, -3] }, // 4 rise + push in / tilt up
  { scale: [1.10, 1.19], x: [3, -2], y: [-3, 3] }, // 5 sink + push in
  { scale: [1.08, 1.14], x: [-2, 2], y: [2, -2] }, // 6 drift — slow, barely-there wander
  { scale: [1.02, 1.32], x: [0, 0], y: [0, 0] }, // 7 dramatic_zoom — fast, large push
  // 8-9 (Task 6 F): punch-ins to opposite sides of the frame. The translate
  // approximates a region focus; the two drift in opposite directions.
  { scale: [1.25, 1.4], x: [6, -2], y: [0, 0] }, // 8 punch_in_left
  { scale: [1.25, 1.4], x: [-6, 2], y: [0, 0] }, // 9 punch_in_right
];

/** Catalog `camera_motion` values (Phase 1 Task 4) mapped to a move. "static"
 *  is handled separately (near-zero motion, not a cycled move). Legacy
 *  shot_type/camera_movement hints from before this task keep resolving the
 *  same way they always did, so old data renders identically. */
const CAMERA_MOTION_MOVE: Record<string, number> = {
  // Task 4 catalog
  slow_push_in: 0,
  push_in: 0,
  pull_out: 1,
  pan_left: 2,
  pan_right: 3,
  tilt_up: 4,
  drift: 6,
  dramatic_zoom: 7,
  punch_in_left: 8,
  punch_in_right: 9,
  // pre-Task-4 shot_type / camera_movement hints (unchanged mapping)
  establishing: 0,
  wide: 0,
  medium: 1,
  tracking: 2,
  pan: 2,
  close_up: 3,
  tilt: 4,
  top_down: 5,
  slow_pull_out: 1,
  tilt_down: 5,
  track: 2,
};

const INTENSITY_GAIN: Record<string, number> = { low: 0.6, medium: 1.0, high: 1.4 };

function moveIndex(hint: string | null | undefined, fallback: number): number {
  if (hint && hint in CAMERA_MOTION_MOVE) return CAMERA_MOTION_MOVE[hint]!;
  return fallback % MOVES.length;
}

/** Eased 0→1 progress across a unit, turned into a transform string. */
function useMotionTransform(
  index: number,
  durationInFrames: number,
  durationSeconds: number,
  opts: { animation?: RenderScene["animation"]; hint?: string | null; intensity?: string | null } = {},
) {
  const frame = useCurrentFrame();
  if (opts.animation === "none" || opts.hint === "static") return "scale(1.01)";

  const p = interpolate(frame, [0, durationInFrames], [0, 1], {
    extrapolateRight: "clamp",
    easing: Easing.inOut(Easing.quad),
  });

  const move = MOVES[moveIndex(opts.hint, index)] ?? MOVES[0]!;
  // Longer units travel more (they'd feel frozen otherwise); short units less.
  // An explicit intensity (Task 4) scales this further, low/medium/high.
  const durationGain = Math.min(1.4, Math.max(0.6, durationSeconds / 8));
  const intensityGain = INTENSITY_GAIN[opts.intensity ?? ""] ?? 1.0;
  const gain = durationGain * intensityGain;
  const mid = (a: number, b: number) => a + (b - a) / 2;

  const scale = interpolate(p, [0, 1], move.scale);
  const x = mid(...move.x) + (interpolate(p, [0, 1], move.x) - mid(...move.x)) * gain;
  const y = mid(...move.y) + (interpolate(p, [0, 1], move.y) - mid(...move.y)) * gain;

  return `scale(${scale}) translate(${x}%, ${y}%)`;
}

/**
 * The visual that fills a scene or a shot. Dispatches on production_method
 * (Phase 1 Task 2 — Media::ProductionDispatcher's choice, carried through the
 * manifest) before falling back to the image lookup, so "text" units render
 * real kinetic typography instead of landing in the plain-span fallback below.
 */
/** motion is an untyped jsonb passthrough on both Scene and Shot; only ever
 *  read one optional string key out of it (Task 4). */
function readIntensity(motion: unknown): string | null {
  if (!motion || typeof motion !== "object") return null;
  const v = (motion as Record<string, unknown>).intensity;
  return typeof v === "string" ? v : null;
}

function Visual({
  assetId,
  transform,
  fallbackText,
  colors,
  assets,
  productionMethod,
  textSpec,
  overlay,
  durationInFrames,
}: {
  assetId: string | null | undefined;
  transform: string;
  fallbackText: string;
  colors: Record<string, string>;
  assets: Assets;
  productionMethod?: string | null;
  textSpec?: unknown;
  overlay?: RenderScene["overlay"];
  durationInFrames: number;
}) {
  if (productionMethod === "text") {
    return (
      <TextAnimationScene
        spec={textSpec}
        fallbackText={fallbackText}
        colors={colors}
        durationInFrames={durationInFrames}
      />
    );
  }

  const asset = assetId ? assets.find((a) => a.id === assetId) : undefined;

  if (asset && asset.type === "image") {
    return (
      <>
        <Img
          src={asset.url}
          style={{
            width: "100%",
            height: "100%",
            objectFit: "cover",
            transform,
            filter: IMAGE_FILTER,
          }}
        />
        <Overlay spec={overlay} colors={colors} durationInFrames={durationInFrames} />
      </>
    );
  }

  return (
    <AbsoluteFill
      style={{ alignItems: "center", justifyContent: "center", padding: "10%", transform }}
    >
      <span
        style={{
          color: colors.text ?? "#f5f5f5",
          fontFamily: "Inter, system-ui, sans-serif",
          fontSize: "5vh",
          fontWeight: 700,
          textAlign: "center",
          lineHeight: 1.3,
        }}
      >
        {fallbackText}
      </span>
    </AbsoluteFill>
  );
}

function ShotClip({
  shot,
  index,
  sceneAssetId,
  fallbackText,
  colors,
  assets,
}: {
  shot: Shot;
  index: number;
  sceneAssetId: string | null;
  fallbackText: string;
  colors: Record<string, string>;
  assets: Assets;
}) {
  const { fps } = useVideoConfig();
  // Remotion scopes useVideoConfig().durationInFrames to the enclosing
  // <Series.Sequence> automatically, so it's already this shot's own length
  // here — but we need the same number again below for TextAnimationScene's
  // duration prop, and it must exactly match the value the parent passed to
  // <Series.Sequence durationInFrames={...}>, so compute it once explicitly
  // rather than reading two different sources for the same quantity.
  const ownDurationInFrames = Math.max(1, Math.round(shot.duration * fps));
  const transform = useMotionTransform(index, ownDurationInFrames, shot.duration, {
    hint: shot.camera_movement ?? shot.shot_type,
    intensity: readIntensity(shot.motion),
  });

  return (
    <AbsoluteFill>
      <Visual
        assetId={shot.asset_id ?? sceneAssetId}
        transform={transform}
        fallbackText={fallbackText}
        colors={colors}
        assets={assets}
        productionMethod={shot.production_method}
        textSpec={shot.text_spec}
        overlay={shot.overlay}
        durationInFrames={ownDurationInFrames}
      />
    </AbsoluteFill>
  );
}

export function SceneClip({ scene, index, assets, template, outgoingTransitionFrames = 0, grade = "clean" }: Props) {
  const { fps } = useVideoConfig();

  const colors = (template.colors ?? {}) as Record<string, string>;
  const background = colors.background ?? "#0a0a0a";
  const fallbackText = scene.caption ?? scene.narration ?? "";

  // Same reasoning as ShotClip's ownDurationInFrames above: Remotion already
  // scopes useVideoConfig().durationInFrames to this scene's enclosing
  // <Series.Sequence>, but this scene's own value is needed again for the
  // no-shots Visual below, so compute it once and reuse it for both.
  const sceneDurationInFrames = Math.max(1, Math.round(scene.duration * fps));
  const sceneCameraMovement =
    scene.camera && typeof scene.camera === "object" && typeof (scene.camera as Record<string, unknown>).movement === "string"
      ? ((scene.camera as Record<string, unknown>).movement as string)
      : null;
  const sceneTransform = useMotionTransform(index, sceneDurationInFrames, scene.duration, {
    animation: scene.animation,
    hint: sceneCameraMovement,
    intensity: readIntensity(scene.motion),
  });

  const shots = scene.shots ?? [];

  return (
    <AbsoluteFill style={{ background }}>
      {shots.length > 0 ? (
        <>
          <Series>
            {shots.map((shot, i) => {
              // Task 4.3 Part 2: only the LAST shot's window needs stretching —
              // it's the one still on screen during the outer sequence's
              // padded tail, where the crossfade into the next scene plays.
              const isLast = i === shots.length - 1;
              const extra = isLast ? outgoingTransitionFrames : 0;
              return (
                <Series.Sequence
                  key={shot.id}
                  durationInFrames={Math.max(1, Math.round(shot.duration * fps)) + extra}
                >
                  <ShotClip
                    shot={shot}
                    index={index + i}
                    sceneAssetId={scene.asset_id}
                    fallbackText={fallbackText}
                    colors={colors}
                    assets={assets}
                  />
                </Series.Sequence>
              );
            })}
          </Series>
          {/* Task 4.3 Part 1: a scene-level overlay (e.g. the Direct panel's
           *  lower_third/keyword_highlight edit) used to be silently dropped
           *  whenever the scene had shots — Visual() only rendered `overlay`
           *  in the no-shots branch above. It's independent of any per-shot
           *  overlay and spans the WHOLE scene, so it's rendered once here,
           *  as a sibling on top of the shot Series rather than nested inside
           *  any one shot. */}
          <Overlay spec={scene.overlay} colors={colors} durationInFrames={sceneDurationInFrames} />
        </>
      ) : (
        <Visual
          assetId={scene.asset_id}
          transform={sceneTransform}
          fallbackText={fallbackText}
          colors={colors}
          assets={assets}
          productionMethod={scene.production_method}
          textSpec={scene.text_spec}
          overlay={scene.overlay}
          durationInFrames={sceneDurationInFrames}
        />
      )}

      <Grade mode={grade} />
    </AbsoluteFill>
  );
}
