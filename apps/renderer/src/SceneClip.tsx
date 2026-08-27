import {
  AbsoluteFill,
  Audio,
  Img,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import type { RenderManifest, RenderScene } from "@clipify/video-schema";
import { Captions } from "./Captions";

type Props = {
  scene: RenderScene;
  assets: RenderManifest["assets"];
  template: RenderManifest["template"];
};

/** Map an animation name to a transform over the scene's frame range. */
function useAnimationTransform(animation: RenderScene["animation"], durationInFrames: number) {
  const frame = useCurrentFrame();
  const p = interpolate(frame, [0, durationInFrames], [0, 1], {
    extrapolateRight: "clamp",
  });

  switch (animation) {
    case "ken_burns":
      return `scale(${1.05 + p * 0.08}) translate(${p * -1.5}%, ${p * -1}%)`;
    case "pan":
      return `scale(1.1) translate(${interpolate(p, [0, 1], [3, -3])}%, 0)`;
    case "scale":
      return `scale(${1 + p * 0.12})`;
    default:
      return "scale(1.03)";
  }
}

export function SceneClip({ scene, assets, template }: Props) {
  const { durationInFrames } = useVideoConfig();
  const frame = useCurrentFrame();

  const transform = useAnimationTransform(scene.animation, durationInFrames);
  const fadeIn = interpolate(frame, [0, 8], [0, 1], { extrapolateRight: "clamp" });

  const colors = (template.colors ?? {}) as Record<string, string>;
  const background = colors.background ?? "#0a0a0a";
  const text = colors.text ?? "#f5f5f5";

  const asset = scene.asset_id ? assets.find((a) => a.id === scene.asset_id) : undefined;

  return (
    <AbsoluteFill style={{ background, opacity: fadeIn }}>
      {asset && asset.type === "image" ? (
        <Img
          src={asset.url}
          style={{ width: "100%", height: "100%", objectFit: "cover", transform }}
        />
      ) : (
        <AbsoluteFill
          style={{
            alignItems: "center",
            justifyContent: "center",
            padding: "10%",
            transform,
          }}
        >
          <span
            style={{
              color: text,
              fontFamily: "Inter, system-ui, sans-serif",
              fontSize: "5vh",
              fontWeight: 700,
              textAlign: "center",
              lineHeight: 1.3,
            }}
          >
            {scene.caption ?? scene.narration ?? ""}
          </span>
        </AbsoluteFill>
      )}

      {scene.narration_audio_url && <Audio src={scene.narration_audio_url} />}

      <Captions cues={scene.captions} />
    </AbsoluteFill>
  );
}
