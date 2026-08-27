# @clipify/renderer

The Remotion video renderer (spec §25). Consumes a **render manifest**
(`@clipify/video-schema` `RenderManifestSchema`, built by
`Media::RenderManifestBuilder` in the API) and produces an MP4.

## Composition

`src/Root.tsx` registers one composition, `ClipifyVideo`, whose props **are** the
manifest (flat, so `schema={RenderManifestSchema}` lines up 1:1).
`calculateMetadata` derives `width` / `height` / `fps` / `durationInFrames` from
the manifest.

- `ClipifyVideo` — a `<Series>` of scene sequences + optional music bed.
- `SceneClip` — background image (`<Img>` with a Ken Burns / pan / scale
  transform) or a text card for non-image visual types, per-scene narration
  `<Audio>`, and timed captions.
- `Captions` — shows the active cue for the current frame.

## Running a render

```bash
node render.mjs <manifest.json> <output.mp4>
```

`render.mjs` calls `ensureBrowser()`, `bundle()`, `selectComposition()`, then
`renderMedia({ codec: "h264" })`. The API's `Video::RenderVideo` service shells
out to exactly this (`RENDER_COMMAND` overrides the command).

## System dependencies

Remotion renders in headless Chrome. On a bare Linux box you must install its
shared libraries first, e.g. on Debian/Ubuntu:

```bash
sudo apt-get install -y libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
  libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
  libxrandr2 libgbm1 libasound2 libpango-1.0-0 libcairo2
```

`npx remotion browser ensure` downloads the Chrome Headless Shell itself.
See https://remotion.dev/docs/miscellaneous/linux-dependencies.

FFmpeg is bundled with `@remotion/renderer` — no separate install needed.

## Studio (visual preview)

```bash
pnpm --filter @clipify/renderer studio
```

Opens the Remotion Studio with the default preview manifest.

## Licensing

Remotion is free for individuals and small teams but requires a **company
license** above a threshold. Review before public launch (spec §25).
