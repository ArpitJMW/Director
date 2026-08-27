import { Composition } from "remotion";
import { ClipifyVideo, totalDurationInFrames } from "./ClipifyVideo";
import { COMPOSITION_ID, RenderManifestSchema, defaultManifest } from "./schema";

export function RemotionRoot() {
  return (
    <Composition
      id={COMPOSITION_ID}
      component={ClipifyVideo}
      schema={RenderManifestSchema}
      defaultProps={defaultManifest}
      calculateMetadata={({ props }) => ({
        width: props.width,
        height: props.height,
        fps: props.fps,
        durationInFrames: totalDurationInFrames(props),
      })}
    />
  );
}
