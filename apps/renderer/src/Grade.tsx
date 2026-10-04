import { AbsoluteFill, random, useCurrentFrame } from "remotion";

/**
 * A light film-grade pass laid over each scene's visual (under the captions).
 * Three cheap, self-contained effects that together pull AI stills away from the
 * "too clean / plastic" look:
 *   1. animated monochrome grain  (breaks up flat gradients, adds texture)
 *   2. vignette                    (focuses the eye, mimics a real lens)
 *   3. a subtle cool-shadow / warm-highlight tone wash
 * No external assets — the grain is an inline SVG turbulence tile.
 */

const GRAIN_TILE =
  "data:image/svg+xml;charset=utf-8," +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="180" height="180">
       <filter id="n">
         <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch"/>
         <feColorMatrix type="saturate" values="0"/>
       </filter>
       <rect width="100%" height="100%" filter="url(#n)"/>
     </svg>`,
  );

export function Grade({
  mode = "clean",
  intensity = 1,
}: {
  /** Task 6.2 Part 2: "clean" leaves the frame untouched; "film" is the
   *  original grade (grain, vignette, tone wash). */
  mode?: "clean" | "film";
  /** 0 disables everything; 1 is the default tasteful amount. */
  intensity?: number;
}) {
  const frame = useCurrentFrame();
  if (mode !== "film" || intensity <= 0) return null;

  // Jump the grain tile around each frame so it shimmers instead of sitting still.
  const gx = Math.round(random(`gx${frame}`) * 180);
  const gy = Math.round(random(`gy${frame}`) * 180);

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {/* tone wash */}
      <AbsoluteFill
        style={{
          background:
            "linear-gradient(180deg, rgba(255,224,196,0.05) 0%, rgba(0,0,0,0) 40%, rgba(10,20,40,0.08) 100%)",
          mixBlendMode: "soft-light",
          opacity: intensity,
        }}
      />
      {/* vignette */}
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(ellipse at center, rgba(0,0,0,0) 55%, rgba(0,0,0,0.38) 100%)",
          mixBlendMode: "multiply",
          opacity: intensity,
        }}
      />
      {/* grain */}
      <AbsoluteFill
        style={{
          backgroundImage: `url("${GRAIN_TILE}")`,
          backgroundRepeat: "repeat",
          backgroundSize: "180px 180px",
          backgroundPosition: `${gx}px ${gy}px`,
          mixBlendMode: "overlay",
          opacity: 0.09 * intensity,
        }}
      />
    </AbsoluteFill>
  );
}
