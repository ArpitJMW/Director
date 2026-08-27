import { AbsoluteFill, Audio, Series } from "remotion";
import type { RenderManifest } from "@clipify/video-schema";
import { SceneClip } from "./SceneClip";

/** Props are the render manifest itself (flat), so Remotion's schema prop lines
 *  up 1:1 with RenderManifestSchema. */
export function ClipifyVideo(manifest: RenderManifest) {
  const fps = manifest.fps;

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <Series>
        {manifest.scenes.map((scene) => (
          <Series.Sequence
            key={scene.id}
            durationInFrames={Math.max(1, Math.round(scene.duration * fps))}
          >
            <SceneClip scene={scene} assets={manifest.assets} template={manifest.template} />
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
