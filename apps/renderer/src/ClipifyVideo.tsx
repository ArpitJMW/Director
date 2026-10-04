import {
  AbsoluteFill,
  Audio,
  interpolate,
  Series,
  useCurrentFrame,
} from "remotion";
import {
  linearTiming,
  TransitionSeries,
  type TransitionPresentation,
  type TransitionPresentationComponentProps,
} from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { wipe } from "@remotion/transitions/wipe";
import type { RenderManifest, RenderScene } from "@clipify/video-schema";
import { Captions } from "./Captions";
import { SceneClip } from "./SceneClip";

/**
 * A scene's `transition` (Phase 1 Task 4) describes how THAT scene enters —
 * i.e. it drives the transition BETWEEN the previous scene and this one.
 * "cut"/unset plays no transition at all. "fade" is the pre-Task-4 schema
 * default — every scene planned before this task already has it stored, and
 * back then no transition ever actually played — so it is ALSO a no-op here
 * (see transitionFramesFor), not an alias for "crossfade"; that keeps an old
 * project's render pixel-identical to before this task. "crossfade" is the
 * new value that actually opts a plan into a dissolve. "fade_from_black"
 * reuses the same dissolve but slower — a deliberate simplification over a
 * true fade-through-black (see the Task 4 final report); genuinely distinct
 * presentations exist for slide/wipe, and "zoom" is a small custom
 * presentation (kept local — no built-in `zoom` presentation ships in
 * @remotion/transitions).
 */
// Task 4.4: crossfade was 10 frames (0.33s at 30fps) — too brief to read as
// a real dissolve (evidence: frames 0.1s apart either side of the boundary
// showed no visible blend). Raised to 16 frames (0.53s), inside the 0.5-0.6s
// target. Only crossfade was in scope for this task; the others are
// untouched.
const TRANSITION_FRAMES: Record<string, number> = {
  crossfade: 16,
  fade: 10,
  fade_from_black: 18,
  slide: 10,
  wipe: 10,
  zoom: 10,
};

const ZoomPresentation = ({
  children,
  presentationDirection,
  presentationProgress,
}: TransitionPresentationComponentProps<Record<string, never>>) => {
  const isEntering = presentationDirection === "entering";
  const scale = isEntering ? 1.12 - 0.12 * presentationProgress : 1;
  const opacity = isEntering ? presentationProgress : 1;
  return (
    <AbsoluteFill style={{ opacity, transform: `scale(${scale})` }}>{children}</AbsoluteFill>
  );
};

function zoom(): TransitionPresentation<Record<string, never>> {
  return { component: ZoomPresentation, props: {} };
}

function presentationFor(transition: string | null | undefined): TransitionPresentation<any> {
  switch (transition) {
    case "slide":
      return slide({ direction: "from-right" });
    case "wipe":
      return wipe({ direction: "from-left" });
    case "zoom":
      return zoom();
    case "fade_from_black":
    case "crossfade":
    case "fade":
    default:
      return fade();
  }
}

function transitionFramesFor(transition: string | null | undefined): number {
  // "fade" is the pre-Task-4 schema default — every scene planned before this
  // task already has it stored, and back then no transition ever actually
  // played. Treating it as a no-op (same as "cut"/unset) is what keeps an old
  // project's render identical to before; "crossfade" is the new value that
  // actually opts a NEW plan into the same dissolve.
  if (!transition || transition === "cut" || transition === "fade") return 0;
  return TRANSITION_FRAMES[transition] ?? 0;
}

/** Props are the render manifest itself (flat), so Remotion's schema prop lines
 *  up 1:1 with RenderManifestSchema. */
export function ClipifyVideo(manifest: RenderManifest) {
  const fps = manifest.fps;
  const frame = useCurrentFrame();
  const total = totalDurationInFrames(manifest);

  // One fade from / to black for the whole film. Scene-to-scene is handled
  // per-scene by the transition layer below (Phase 1 Task 4) — per-scene
  // opacity fades over a torn-down previous scene caused black flashes.
  const opacity = interpolate(
    frame,
    [0, 12, Math.max(13, total - 12), total],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill style={{ background: "#000", opacity }}>
      {/* VISUAL layer: scenes overlap by each transition's frame count, via
       *  @remotion/transitions. Each scene's own Sequence duration is padded
       *  by the frames its OUTGOING transition borrows, so every scene's
       *  actual start frame still lands exactly on sum(previous durations) —
       *  frame-for-frame the same position as the untouched AUDIO layer
       *  below. See the Task 4 final report for the derivation; this is what
       *  keeps a transition from ever touching narration timing. */}
      <TransitionSeries>
        {manifest.scenes.flatMap((scene, i) => {
          const next = manifest.scenes[i + 1];
          const outgoingFrames = next ? transitionFramesFor(next.transition) : 0;
          const ownFrames = Math.max(1, Math.round(scene.duration * fps)) + outgoingFrames;

          const sequence = (
            <TransitionSeries.Sequence key={scene.id} durationInFrames={ownFrames}>
              <SceneClip
                scene={scene}
                index={i}
                assets={manifest.assets}
                template={manifest.template}
                outgoingTransitionFrames={outgoingFrames}
                grade={manifest.look?.grade ?? "clean"}
              />
            </TransitionSeries.Sequence>
          );

          if (outgoingFrames === 0) return [sequence];

          return [
            sequence,
            <TransitionSeries.Transition
              key={`${scene.id}-to-${next!.id}`}
              timing={linearTiming({ durationInFrames: outgoingFrames })}
              presentation={presentationFor(next!.transition)}
            />,
          ];
        })}
      </TransitionSeries>

      {/* AUDIO + CAPTIONS layer: unchanged since Phase 1 Task 2 — one
       *  non-overlapping Sequence per scene, exactly the layout Tasks
       *  2.4-2.7 tuned narration timing against. The transition layer above
       *  never touches this. */}
      <Series>
        {manifest.scenes.map((scene: RenderScene) => (
          <Series.Sequence
            key={scene.id}
            durationInFrames={Math.max(1, Math.round(scene.duration * fps))}
          >
            {scene.narration_audio_url && <Audio src={scene.narration_audio_url} />}
            <Captions cues={scene.captions} />
          </Series.Sequence>
        ))}
      </Series>

      {manifest.music && (
        <Audio src={manifest.music.url} volume={manifest.music.level} loop />
      )}
    </AbsoluteFill>
  );
}

export function totalDurationInFrames(manifest: RenderManifest): number {
  return Math.max(
    1,
    manifest.scenes.reduce(
      (sum, scene) => sum + Math.round(scene.duration * manifest.fps),
      0,
    ),
  );
}
