# Video Engine

Rendering the final MP4 (spec §20 step 15, §25, §28). Nothing holds an HTTP
request open — the API returns a job immediately and the render runs in Sidekiq.

## Flow

```
POST /api/v1/projects/:id/render
  → GenerationJob(stage: render) + project.start_render! + Sidekiq enqueue
  → Generation::RenderJob (queue: render)
      1. create VideoRender (queued)
      2. Media::RenderManifestBuilder → manifest, stored on the render
      3. video_render.start!  (rendering)
      4. Video::RenderVideo → shells out to the Remotion renderer → MP4 bytes
      5. video_render.start_upload!  (uploading)
      6. Asset.store!(asset_type: video) → video_render.output_asset
      7. video_render.complete!  (completed)
    on error: VideoRender → failed, re-raise (Sidekiq retry ×2)
```

## Render manifest (spec §20 step 14)

`Media::RenderManifestBuilder` resolves the storyboard into
`@clipify/video-schema` `RenderManifestSchema` shape:

- `width`/`height` from the project aspect ratio (1920×1080 / 1080×1920 / 1080²),
  `fps` 30
- `template` — the pinned `template_version.config` (design language, spec §24)
- `scenes[]` — the §19 Scene JSON contract + `narration_audio_url` (absolute,
  6-hour signed URL), `alignment`, `captions[]`
- `assets[]` — resolved image/audio assets with absolute signed URLs
- `music` — `null` (music stage not built)

Absolute URLs use `RENDER_ASSET_BASE_URL` (default `http://localhost:3000`) so a
renderer on another host can fetch them.

## The renderer — `apps/renderer`

Remotion project (`@clipify/renderer`). One composition, `ClipifyVideo`, whose
props are the manifest. `Video::RenderVideo` runs `node apps/renderer/render.mjs
<manifest.json> <out.mp4>` (override with `RENDER_COMMAND`). See
[`apps/renderer/README.md`](../apps/renderer/README.md) — **note the Linux system
dependencies for headless Chrome**.

## Not built

- Music bed + template audio-ducking rules
- Non-image visual types in the composition (chart/timeline/map/quote card
  currently render as a text card)
- `@remotion/transitions` (scenes currently hard-cut with an 8-frame fade-in)
- Thumbnail generation
