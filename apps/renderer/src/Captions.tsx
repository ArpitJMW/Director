import { useCurrentFrame, useVideoConfig } from "remotion";
import type { CaptionCue } from "@clipify/video-schema";

export function Captions({ cues }: { cues: CaptionCue[] }) {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;

  const active = cues.find((cue) => t >= cue.start && t <= cue.end) ?? null;
  if (!active) return null;

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: "8%",
        display: "flex",
        justifyContent: "center",
        padding: "0 8%",
      }}
    >
      <span
        style={{
          background: "rgba(0,0,0,0.6)",
          color: "white",
          fontFamily: "Inter, system-ui, sans-serif",
          fontSize: "3.2vh",
          fontWeight: 600,
          lineHeight: 1.3,
          padding: "0.4em 0.7em",
          borderRadius: "0.3em",
          textAlign: "center",
        }}
      >
        {active.text}
      </span>
    </div>
  );
}
