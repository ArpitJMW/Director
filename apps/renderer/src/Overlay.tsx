import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import type { Overlay as OverlaySpec } from "@clipify/video-schema";

/**
 * On-image decoration for "image" units (Phase 1 Task 4 Part A). Reads the
 * manifest's `overlay` field (Media::ProductionDispatcher never touches
 * this — it's a purely presentational layer on top of whichever image
 * ended up selected) and renders one of four polished, self-contained
 * treatments. Absent/`type: "none"` renders nothing, so a scene without an
 * overlay looks exactly as it did before this task.
 *
 * Task 4.3 Part 1: enters, holds, and EXITS before the unit's own end
 * (previously held at full opacity right up until whatever unmounted it —
 * invisible in isolation but jarring once Part 2 made the unit's last frame
 * actually persist through a crossfade tail).
 *
 * Task 4.4: real-render evidence showed the lower_third touching the left
 * edge (its padding had 0 on the sides, only top/bottom), reading as small
 * and undergrounded rather than a real lower third. All four treatments now
 * share one SAFE_SIDE/SAFE_TOP/SAFE_BOTTOM inset system (previously each had
 * its own ad hoc 6%/7%/10% padding), so none can ever touch an edge or the
 * caption zone, and the lower_third got a proper two-line-capable plate.
 */
const ENTER_FRAMES = 12; // 0.4s @ 30fps (Task 4.4: was 14/~0.47s)
const EXIT_FRAMES = 12;
/** Shared safe-area insets (Task 4.4) — every overlay type uses these, so
 *  sizing/edge clearance reads as one consistent system rather than four
 *  independently-tuned ones. SAFE_BOTTOM keeps every bottom-anchored overlay
 *  clear of Captions.tsx's own bottom:8% zone (which can extend up to
 *  roughly 18-20% of frame height once padded). SAFE_SIDE keeps the
 *  ≥5%-of-width inset the lower_third was specifically missing. */
// Task 5C root cause: CSS percentage padding is relative to the element's
// WIDTH on all four sides, so the old `24%` bottom inset was 24% of 1920px
// (~460px) — which lifted every bottom-anchored overlay to ~55-57% of the
// frame height. Vertical insets are therefore in vh, horizontal in vw.
const SAFE_SIDE = "6vw";
const SAFE_TOP = "6vh";
const SAFE_BOTTOM = "24vh";

function useEnterExit(durationInFrames: number) {
  const frame = useCurrentFrame();
  const enter = interpolate(frame, [0, ENTER_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const exitStart = Math.max(ENTER_FRAMES, durationInFrames - EXIT_FRAMES);
  const exit = interpolate(frame, [exitStart, durationInFrames], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.in(Easing.cubic),
  });
  return Math.min(enter, exit);
}

const FONT = "Inter, system-ui, sans-serif";

export function Overlay({
  spec,
  colors,
  durationInFrames = Infinity,
}: {
  spec: OverlaySpec | null | undefined;
  colors: Record<string, string>;
  /** This unit's (scene's or shot's) own on-screen duration, so the overlay
   *  can time its exit to end before the unit does (Task 4.3 Part 1). */
  durationInFrames?: number;
}) {
  const p = useEnterExit(durationInFrames);
  if (!spec || spec.type === "none" || !spec.text) return null;

  const accent = colors.accent ?? "#f5c76b";

  if (spec.type === "keyword_highlight") {
    return (
      <AbsoluteFill style={{ alignItems: "flex-start", justifyContent: "flex-end", padding: `${SAFE_TOP} ${SAFE_SIDE} ${SAFE_BOTTOM} ${SAFE_SIDE}` }}>
        <div
          style={{
            opacity: p,
            transform: `translateY(${(1 - p) * 14}px)`,
            background: accent,
            color: "#111",
            fontFamily: FONT,
            fontWeight: 800,
            fontSize: "3.6vh",
            padding: "0.4em 0.9em",
            borderRadius: "999px",
            letterSpacing: "0.01em",
            boxShadow: "0 0.15em 0.6em rgba(0,0,0,0.35)",
          }}
        >
          {spec.text}
        </div>
      </AbsoluteFill>
    );
  }

  if (spec.type === "lower_third") {
    // Task 4.4: a real lower third — inset from both edges (was flush left),
    // a solid plate behind the text (was near-transparent, unreadable on a
    // bright photo), and two-line capable: `text` as the title, `value` (the
    // same field stat_callout uses for its number — unused by lower_third
    // until now) as an optional subtitle line underneath.
    return (
      <AbsoluteFill style={{ alignItems: "flex-start", justifyContent: "flex-end", padding: `${SAFE_TOP} ${SAFE_SIDE} ${SAFE_BOTTOM} ${SAFE_SIDE}` }}>
        <div
          style={{
            opacity: p,
            transform: `translateX(${(1 - p) * -28}px)`,
            display: "flex",
            alignItems: "stretch",
            maxWidth: "70%",
            boxShadow: "0 0.2em 0.9em rgba(0,0,0,0.45)",
          }}
        >
          <div style={{ width: "0.3em", flexShrink: 0, background: accent }} />
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: "0.2em",
              justifyContent: "center",
              padding: "0.6em 1.1em",
              background: "rgba(8,8,8,0.82)",
            }}
          >
            <span
              style={{
                fontFamily: FONT,
                fontWeight: 700,
                fontSize: "3.2vh",
                lineHeight: 1.2,
                color: "#f8f8f8",
              }}
            >
              {spec.text}
            </span>
            {spec.value && (
              <span
                style={{
                  fontFamily: FONT,
                  fontWeight: 500,
                  fontSize: "2.1vh",
                  lineHeight: 1.2,
                  color: "rgba(245,245,245,0.78)",
                }}
              >
                {spec.value}
              </span>
            )}
          </div>
        </div>
      </AbsoluteFill>
    );
  }

  if (spec.type === "stat_callout") {
    return (
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", padding: `${SAFE_TOP} ${SAFE_SIDE} ${SAFE_BOTTOM} ${SAFE_SIDE}` }}>
        <div
          style={{
            opacity: p,
            transform: `scale(${0.9 + p * 0.1})`,
            textAlign: "center",
            background: "rgba(10,10,10,0.42)",
            borderRadius: "0.5em",
            padding: "0.6em 1em",
          }}
        >
          {spec.value && (
            <div
              style={{
                fontFamily: FONT,
                fontWeight: 900,
                fontSize: "13vh",
                lineHeight: 1,
                color: accent,
                textShadow: "0 0.06em 0.3em rgba(0,0,0,0.6)",
              }}
            >
              {spec.value}
            </div>
          )}
          <div
            style={{
              marginTop: "0.3em",
              fontFamily: FONT,
              fontWeight: 700,
              fontSize: "3.4vh",
              color: "#f5f5f5",
              textShadow: "0 0.05em 0.2em rgba(0,0,0,0.7)",
            }}
          >
            {spec.text}
          </div>
        </div>
      </AbsoluteFill>
    );
  }

  // title_card
  return (
    <AbsoluteFill style={{ alignItems: "flex-start", justifyContent: "flex-start", padding: `${SAFE_TOP} ${SAFE_SIDE} ${SAFE_BOTTOM} ${SAFE_SIDE}` }}>
      <div
        style={{
          opacity: p,
          transform: `translateY(${(1 - p) * -14}px)`,
          background: "rgba(10,10,10,0.42)",
          borderRadius: "0.35em",
          padding: "0.5em 0.7em",
          fontFamily: FONT,
          fontWeight: 800,
          fontSize: "5vh",
          lineHeight: 1.15,
          color: "#f5f5f5",
          maxWidth: "70%",
          textShadow: "0 0.06em 0.3em rgba(0,0,0,0.55)",
        }}
      >
        {spec.text}
        <div style={{ marginTop: "0.25em", width: "3em", height: "0.09em", background: accent }} />
      </div>
    </AbsoluteFill>
  );
}
