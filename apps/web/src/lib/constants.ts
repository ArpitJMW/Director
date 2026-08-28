import type { ProjectFormat, VisualStyle } from "@clipify/types";

export const FORMATS: { value: ProjectFormat; label: string }[] = [
  { value: "youtube_long", label: "YouTube (16:9)" },
  { value: "youtube_short", label: "Short (9:16)" },
  { value: "reel", label: "Reel (9:16)" },
];

export const VISUAL_STYLES: { value: VisualStyle; label: string }[] = [
  { value: "cinematic", label: "Cinematic" },
  { value: "photorealistic", label: "Photorealistic" },
  { value: "wildlife_documentary", label: "Wildlife documentary" },
  { value: "documentary", label: "Documentary" },
  { value: "3d_animation", label: "3D animation" },
  { value: "illustration", label: "Illustration" },
  { value: "anime", label: "Anime" },
  { value: "watercolor", label: "Watercolor" },
];
