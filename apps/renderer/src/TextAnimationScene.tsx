import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import type { TextSpec } from "@clipify/video-schema";

/**
 * Renders the structured spec Media::TextAnimationSpecService builds for an
 * asset_strategy "text" scene/shot (Phase 1 Task 2 — kinetic typography as a
 * real production method, not the plain-span fallback used when nothing else
 * matched). Phase 1 Task 4 adds a `text_style` catalog on top of the
 * original (and still default) stagger-reveal treatment: a beat whose
 * content genuinely is a place list, a timeline of dated steps, a key
 * number, or a quotable line now gets a style built for that shape, instead
 * of every text beat looking the same.
 */
const FONT = "Inter, system-ui, sans-serif";

// Phase 1 Task 4.2 Part C: the spec builder (Media::TextAnimationSpecService)
// already caps items/unit length before this ever reaches the renderer —
// these are a renderer-side backstop in case a spec somehow arrives
// un-sanitized (a stale row from before Task 4.2, a manifest hand-built for
// testing), so a long input degrades gracefully here too, not just server-side.
const MAX_ITEMS = 5;
const MAX_ITEM_CHARS = 44;

function truncate(text: string, limit: number): string {
  return text.length <= limit ? text : `${text.slice(0, limit - 1).trimEnd()}…`;
}

/** Shrinks a base font size as content length grows past a soft limit, down
 *  to a floor — so a long input scales down instead of overflowing the
 *  frame. Every text_style that shows arbitrary-length content (quote,
 *  list_reveal, timeline, big_number) uses this instead of a fixed vh.
 *  `perChar` (vh shed per character past softLimit) needs to scale with
 *  `base` — a 16vh number needs a far bigger per-char step than a 5.6vh
 *  quote to actually shrink enough to fit; callers with a large base (e.g.
 *  BigNumber) must pass an explicitly larger perChar, not rely on the
 *  default (tuned for the ~2-6vh styles). */
function scaledFontVh(
  totalChars: number,
  { base, min, softLimit, perChar = 0.035 }: { base: number; min: number; softLimit: number; perChar?: number },
) {
  if (totalChars <= softLimit) return base;
  return Math.max(min, base - (totalChars - softLimit) * perChar);
}

function readSpec(raw: unknown): TextSpec {
  if (!raw || typeof raw !== "object") return { text_style: "stagger_reveal" };
  const spec = raw as Record<string, unknown>;
  const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : undefined);
  const textStyle = typeof spec.text_style === "string" ? spec.text_style : "stagger_reveal";
  const items = strings(spec.items)
    ?.slice(0, MAX_ITEMS)
    .map((i) => truncate(i, MAX_ITEM_CHARS));
  return {
    lines: strings(spec.lines),
    emphasis: strings(spec.emphasis),
    text_style: (TEXT_STYLE_VALUES.has(textStyle) ? textStyle : "stagger_reveal") as TextSpec["text_style"],
    items,
    number: typeof spec.number === "number" || typeof spec.number === "string" ? spec.number : undefined,
    unit: typeof spec.unit === "string" ? truncate(spec.unit, 12) : undefined,
  };
}

const TEXT_STYLE_VALUES = new Set([
  "stagger_reveal", "punch_in", "big_number", "quote", "list_reveal", "timeline",
]);

function emphasize(line: string, emphasis: Set<string>, accent: string) {
  return line.split(" ").map((word, wi) => {
    const bare = word.toLowerCase().replace(/[^a-z']/g, "");
    return (
      <span key={wi} style={{ color: emphasis.has(bare) ? accent : "inherit", marginRight: "0.32em" }}>
        {word}
      </span>
    );
  });
}

type StyleProps = {
  lines: string[];
  items: string[];
  emphasis: Set<string>;
  number?: string | number;
  unit?: string;
  colors: Record<string, string>;
  durationInFrames: number;
  frame: number;
};

function StaggerReveal({ lines, emphasis, colors, durationInFrames, frame }: StyleProps) {
  const perLine = durationInFrames / lines.length;
  const reveal = Math.min(10, perLine * 0.4);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "1.6vh" }}>
      {lines.map((line, i) => {
        const start = i * perLine;
        const opacity = interpolate(
          frame,
          [start, start + reveal, start + perLine - reveal, start + perLine],
          [0, 1, 1, 0.9],
          { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
        );
        const rise = interpolate(frame, [start, start + reveal], [18, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
        return (
          <div
            key={i}
            style={{
              opacity,
              transform: `translateY(${rise}px)`,
              fontFamily: FONT,
              fontSize: "6.4vh",
              fontWeight: 800,
              textAlign: "center",
              lineHeight: 1.15,
              color: colors.text ?? "#f5f5f5",
            }}
          >
            {emphasize(line, emphasis, colors.accent ?? "#f5c76b")}
          </div>
        );
      })}
    </div>
  );
}

/** Punchy pop-in — one line at a time, fast scale+opacity rather than a slow
 *  rise. Suited to a hook/punchline beat. */
function PunchIn({ lines, emphasis, colors, durationInFrames, frame }: StyleProps) {
  const perLine = durationInFrames / lines.length;
  const punch = Math.min(8, perLine * 0.3);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "1.6vh" }}>
      {lines.map((line, i) => {
        const start = i * perLine;
        const p = interpolate(frame, [start, start + punch], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.out(Easing.back(2)),
        });
        const opacity = interpolate(frame, [start, start + punch * 0.6], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
        return (
          <div
            key={i}
            style={{
              opacity,
              transform: `scale(${0.7 + p * 0.3})`,
              fontFamily: FONT,
              fontSize: "7.2vh",
              fontWeight: 800,
              textAlign: "center",
              lineHeight: 1.15,
              color: colors.text ?? "#f5f5f5",
            }}
          >
            {emphasize(line, emphasis, colors.accent ?? "#f5c76b")}
          </div>
        );
      })}
    </div>
  );
}

/** A single number counts up from 0 to its target, with the caption line(s)
 *  settling in underneath. For a beat whose whole point IS the number. */
function BigNumber({ lines, number, unit, colors, durationInFrames, frame }: StyleProps) {
  const target = typeof number === "string" ? parseFloat(number) : number ?? 0;
  const isInt = Number.isFinite(target) && Number.isInteger(target);
  const countFrames = Math.min(36, durationInFrames * 0.5);
  const p = interpolate(frame, [0, countFrames], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const shown = Number.isFinite(target) ? target * p : 0;
  const label = Number.isFinite(target)
    ? (isInt ? Math.round(shown).toLocaleString() : shown.toFixed(1))
    : String(number ?? "");
  const captionOpacity = interpolate(frame, [countFrames, countFrames + 10], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Task 4.2 Part C: an inline unit sharing the number's own line was how
  // this used to overflow — a long unit (even capped to 12 chars) forced a
  // MID-WORD wrap right next to a giant number, e.g. "1,234,567percen" /
  // "tage-...". A short unit ("%", "x") still reads fine inline; anything
  // longer goes on its own line below, at a fixed, comfortably-fitting size,
  // instead of sharing width with the number at all. The number's own font
  // scales down for a long number regardless (a 7-digit count-up needs less
  // room than "42", but still shouldn't be assumed to always fit at 16vh).
  const numberFontSize = scaledFontVh(label.length, { base: 16, min: 9, softLimit: 5, perChar: 0.9 });
  const unitInline = (unit?.length ?? 0) <= 3;

  return (
    <div style={{ textAlign: "center", maxWidth: "84%" }}>
      <div
        style={{
          fontFamily: FONT,
          fontWeight: 900,
          fontSize: `${numberFontSize}vh`,
          lineHeight: 1,
          color: colors.accent ?? "#f5c76b",
        }}
      >
        {label}
        {unit && unitInline ? <span style={{ fontSize: "0.5em", marginLeft: "0.1em" }}>{unit}</span> : null}
      </div>
      {unit && !unitInline && (
        <div
          style={{
            marginTop: "0.2em",
            fontFamily: FONT,
            fontWeight: 700,
            fontSize: "3.2vh",
            color: colors.accent ?? "#f5c76b",
            overflowWrap: "break-word",
          }}
        >
          {unit}
        </div>
      )}
      {lines.length > 0 && (
        <div
          style={{
            marginTop: "0.5em",
            opacity: captionOpacity,
            fontFamily: FONT,
            fontWeight: 700,
            fontSize: "4vh",
            color: colors.text ?? "#f5f5f5",
            overflowWrap: "break-word",
            wordBreak: "break-word",
          }}
        >
          {lines.join(" ")}
        </div>
      )}
    </div>
  );
}

/** Centered quotation, with a large accent-colored quotation mark. Font
 *  scales down for a long quote (Task 4.2 Part C) rather than overflowing —
 *  a 60-char quote gets the full 5.6vh; well beyond that it shrinks. */
function Quote({ lines, colors }: StyleProps) {
  const text = lines.join(" ");
  const fontSize = scaledFontVh(text.length, { base: 5.6, min: 3.4, softLimit: 60 });
  return (
    <div style={{ textAlign: "center", maxWidth: "80%" }}>
      <div style={{ fontFamily: FONT, fontSize: "10vh", color: colors.accent ?? "#f5c76b", lineHeight: 0.6 }}>“</div>
      <div
        style={{
          fontFamily: FONT,
          fontWeight: 600,
          fontStyle: "italic",
          fontSize: `${fontSize}vh`,
          lineHeight: 1.25,
          color: colors.text ?? "#f5f5f5",
          overflowWrap: "break-word",
          wordBreak: "break-word",
        }}
      >
        {text}
      </div>
    </div>
  );
}

/** Items appear one by one and stay listed — for a place list ("Venice,
 *  Paris, Mainz") or any short enumerable set. Exactly the beat class that
 *  used to get routed to a gibberish-labelled map/document image.
 *
 *  Task 4.3 Part 3: the reveal used to be capped at 24 frames/item (0.8s)
 *  regardless of how long the unit actually was on screen — for a typical
 *  7-8s scene with 3 items that meant every item had appeared, and the beat
 *  sat static, within the first ~1.5s. Each item's entrance is now spread
 *  across the FULL unit duration instead, so the reveal reads as paced with
 *  the narration rather than front-loaded. */
function ListReveal({ lines, items, colors, durationInFrames, frame }: StyleProps) {
  const n = Math.max(items.length, 1);
  const perItem = durationInFrames / n;
  const reveal = Math.min(14, Math.max(6, perItem * 0.35));
  // Task 4.2 Part C: scale by the longest item, not the average — one long
  // name in an otherwise-short list is still what would overflow. Base/min
  // raised (Task 4.3 Part 3 — "large centered layout") vs the original
  // 5.6/3.2vh; softLimit raised to match so a short list still gets the full
  // larger size instead of shrinking prematurely.
  const longest = items.reduce((max, i) => Math.max(max, i.length), 0);
  const fontSize = scaledFontVh(longest, { base: 7.2, min: 3.6, softLimit: 14, perChar: 0.14 });
  // Optional small heading (Task 4.3 Part 3): the scene's own caption/lines,
  // already computed for every text_style but previously unused by this one.
  // Only shown when it says something the list itself doesn't already.
  const heading = lines[0] && lines[0].trim() !== items.join(" ").trim() ? lines[0] : null;
  const headingOpacity = interpolate(frame, [0, 10], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", maxWidth: "84%" }}>
      {heading && (
        <div
          style={{
            opacity: headingOpacity,
            fontFamily: FONT,
            fontWeight: 600,
            fontSize: "2.6vh",
            letterSpacing: "0.02em",
            textTransform: "uppercase",
            color: colors.accent ?? "#f5c76b",
            marginBottom: "2.4vh",
            textAlign: "center",
          }}
        >
          {heading}
        </div>
      )}
      <div style={{ display: "flex", flexDirection: "column", gap: "2.6vh", alignItems: "flex-start" }}>
        {items.map((item, i) => {
          const start = i * perItem;
          const opacity = interpolate(frame, [start, start + reveal], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });
          const slide = interpolate(frame, [start, start + reveal], [-24, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.out(Easing.quad),
          });
          return (
            <div
              key={i}
              style={{
                opacity,
                transform: `translateX(${slide}px)`,
                display: "flex",
                alignItems: "center",
                gap: "0.6em",
              }}
            >
              <span
                style={{
                  width: "0.55em",
                  height: "0.55em",
                  flexShrink: 0,
                  borderRadius: "0.15em",
                  background: colors.accent ?? "#f5c76b",
                }}
              />
              <span
                style={{
                  fontFamily: FONT,
                  fontWeight: 700,
                  fontSize: `${fontSize}vh`,
                  color: colors.text ?? "#f5f5f5",
                  overflowWrap: "break-word",
                  wordBreak: "break-word",
                }}
              >
                {item}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** A horizontal line of 3-5 dated/ordered steps, with a playhead dot that
 *  travels along it and lights up each step as it passes. For a beat that
 *  narrates a sequence of developments over time. */
function Timeline({ lines, items, colors, durationInFrames, frame }: StyleProps) {
  const n = Math.max(items.length, 1);
  // Task 4.2 Part C: more/longer steps get a smaller label font, and labels
  // wrap within their column instead of overflowing it.
  const longest = items.reduce((max, i) => Math.max(max, i.length), 0);
  const fontSize = scaledFontVh(longest + n * 3, { base: 3, min: 1.8, softLimit: 20 });
  const progressEnd = Math.max(9, durationInFrames - 8);
  const progress = interpolate(frame, [8, progressEnd], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.inOut(Easing.quad),
  });
  // Task 4.3 Part 3: optional small heading, same idea as ListReveal.
  const heading = lines[0] && lines[0].trim() !== items.join(" ").trim() ? lines[0] : null;
  const headingOpacity = interpolate(frame, [0, 10], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <div style={{ width: "82%" }}>
      {heading && (
        <div
          style={{
            opacity: headingOpacity,
            fontFamily: FONT,
            fontWeight: 600,
            fontSize: "2.6vh",
            letterSpacing: "0.02em",
            textTransform: "uppercase",
            color: colors.accent ?? "#f5c76b",
            marginBottom: "3vh",
            textAlign: "center",
          }}
        >
          {heading}
        </div>
      )}
      <div style={{ position: "relative", height: "0.14em", background: "rgba(255,255,255,0.25)", borderRadius: "999px" }}>
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            height: "100%",
            width: `${progress * 100}%`,
            background: colors.accent ?? "#f5c76b",
            borderRadius: "999px",
          }}
        />
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", marginTop: "2.2vh" }}>
        {items.map((item, i) => {
          const at = n === 1 ? 0 : i / (n - 1);
          const active = progress >= at - 0.02;
          const lower = Math.max(0, at - 0.12);
          const upper = Math.max(lower + 0.001, at);
          const opacity = interpolate(progress, [lower, upper], [0.35, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });
          return (
            <div key={i} style={{ maxWidth: `${90 / n}%`, textAlign: "center", opacity }}>
              <div
                style={{
                  width: "0.7em",
                  height: "0.7em",
                  margin: "0 auto 1vh",
                  borderRadius: "50%",
                  background: active ? colors.accent ?? "#f5c76b" : "rgba(255,255,255,0.4)",
                }}
              />
              <div
                style={{
                  fontFamily: FONT,
                  fontWeight: 700,
                  fontSize: `${fontSize}vh`,
                  color: colors.text ?? "#f5f5f5",
                  overflowWrap: "break-word",
                  wordBreak: "break-word",
                }}
              >
                {item}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function TextAnimationScene({
  spec,
  fallbackText,
  colors,
  /** This unit's OWN duration in frames — pass shot/scene-local, never the
   *  composition-wide videoConfig value (that one covers the whole render). */
  durationInFrames,
}: {
  spec: unknown;
  fallbackText: string;
  colors: Record<string, string>;
  durationInFrames: number;
}) {
  const frame = useCurrentFrame();
  const parsed = readSpec(spec);
  const lines = parsed.lines?.length ? parsed.lines : [fallbackText];
  const items = parsed.items?.length ? parsed.items : lines;
  const emphasis = new Set((parsed.emphasis ?? []).map((w) => w.toLowerCase()));
  const props: StyleProps = {
    lines,
    items,
    emphasis,
    number: parsed.number ?? undefined,
    unit: parsed.unit ?? undefined,
    colors,
    durationInFrames,
    frame,
  };

  // Task 4.3 Part 3: a slow, subtle "breathing" glow so a text-only unit
  // isn't a flat, static color field for its whole duration — cheap (one
  // radial-gradient position driven by frame), and restrained enough to
  // stay consistent with Grade's own vignette rather than competing with it.
  const period = 260; // ~8.7s at 30fps — one full cycle rarely completes within a single unit
  const breathe = (Math.sin((frame / period) * Math.PI * 2) + 1) / 2; // 0..1
  const glowX = 50 + (breathe - 0.5) * 16;
  const glowY = 42 + (breathe - 0.5) * 10;

  return (
    <AbsoluteFill
      style={{
        background: colors.background ?? "#0a0a0a",
      }}
    >
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse at ${glowX}% ${glowY}%, ${colors.accent ?? "#f5c76b"}14 0%, rgba(0,0,0,0) 55%)`,
        }}
      />
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          padding: "8% 10%",
        }}
      >
        {parsed.text_style === "punch_in" && <PunchIn {...props} />}
        {parsed.text_style === "big_number" && <BigNumber {...props} />}
        {parsed.text_style === "quote" && <Quote {...props} />}
        {parsed.text_style === "list_reveal" && <ListReveal {...props} />}
        {parsed.text_style === "timeline" && <Timeline {...props} />}
        {parsed.text_style === "stagger_reveal" && <StaggerReveal {...props} />}
      </AbsoluteFill>
    </AbsoluteFill>
  );
}
