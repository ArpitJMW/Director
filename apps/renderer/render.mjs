// CLI entry the Rails render job shells out to:
//   node render.mjs <manifest.json> <output.mp4>
// Bundles the Remotion project, resolves the composition from the manifest, and
// renders an MP4. The manifest is already validated Rails-side.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bundle } from "@remotion/bundler";
import { ensureBrowser, renderMedia, selectComposition } from "@remotion/renderer";

const here = path.dirname(fileURLToPath(import.meta.url));
const COMPOSITION_ID = "ClipifyVideo";

async function main() {
  const [manifestPath, outputPath] = process.argv.slice(2);
  if (!manifestPath || !outputPath) {
    console.error("usage: node render.mjs <manifest.json> <output.mp4>");
    process.exit(2);
  }

  const manifest = JSON.parse(readFileSync(manifestPath, "utf-8"));

  await ensureBrowser();

  const serveUrl = await bundle({ entryPoint: path.join(here, "src/index.ts") });

  const composition = await selectComposition({
    serveUrl,
    id: COMPOSITION_ID,
    inputProps: manifest,
  });

  await renderMedia({
    serveUrl,
    composition,
    codec: "h264",
    outputLocation: outputPath,
    inputProps: manifest,
    onProgress: ({ progress }) => {
      process.stderr.write(`\rrender ${Math.round(progress * 100)}%`);
    },
  });

  process.stderr.write("\n");
  console.log(outputPath);
}

main().catch((err) => {
  console.error(err?.stack ?? String(err));
  process.exit(1);
});
