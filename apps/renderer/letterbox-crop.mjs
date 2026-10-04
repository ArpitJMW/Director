// CLI: node letterbox-crop.mjs <input> <output> <aspectW> <aspectH>
// Task 5C — removes near-black letterbox bars from a generated image, then
// centre-crops it to the target aspect. A normal image (no bars, aspect already
// right) is copied through byte-for-byte. Prints one JSON line on stdout.

import { copyFile } from "node:fs/promises";
import sharp from "sharp";

const DARK_LUMA = 24;          // a pixel at or below this counts as black
const DARK_SHARE = 0.97;       // a row/column is a bar when this share of it is black…
const DARK_MEAN = 20;          // …and its mean luma is this low
const MAX_BAR_SHARE = 0.25;    // never crop more than this share of a side
const MIN_BAR_SHARE = 0.02;    // ignore slivers thinner than this (natural dark edges)
const ASPECT_TOLERANCE = 0.01; // treat ratios this close as already correct

const [inputPath, outputPath, aspectWStr, aspectHStr] = process.argv.slice(2);
const aspect = Number(aspectWStr) / Number(aspectHStr);

function isBarLine(pixels) {
  let dark = 0;
  let sum = 0;
  for (const v of pixels) {
    sum += v;
    if (v <= DARK_LUMA) dark += 1;
  }
  return dark / pixels.length >= DARK_SHARE && sum / pixels.length <= DARK_MEAN;
}

// Scans from one edge inward and returns how many lines are black bar.
function barDepth(lineAt, maxDepth, minDepth) {
  let depth = 0;
  while (depth < maxDepth && isBarLine(lineAt(depth))) depth += 1;
  return depth >= minDepth ? depth : 0;
}

export function detectBars(gray, width, height) {
  const maxRows = Math.floor(height * MAX_BAR_SHARE);
  const maxCols = Math.floor(width * MAX_BAR_SHARE);
  const minRows = Math.max(4, Math.round(height * MIN_BAR_SHARE));
  const minCols = Math.max(4, Math.round(width * MIN_BAR_SHARE));

  const row = (y) => gray.subarray(y * width, (y + 1) * width);
  const top = barDepth((i) => row(i), maxRows, minRows);
  const bottom = barDepth((i) => row(height - 1 - i), maxRows, minRows);

  const innerRows = height - top - bottom;
  const col = (x) => {
    const out = new Uint8Array(innerRows);
    for (let k = 0; k < innerRows; k += 1) out[k] = gray[(top + k) * width + x];
    return out;
  };
  const left = barDepth((i) => col(i), maxCols, minCols);
  const right = barDepth((i) => col(width - 1 - i), maxCols, minCols);

  return { top, bottom, left, right };
}

export function coverCrop(rect, width, height, aspect) {
  let { left, top } = rect;
  let w = width - rect.left - rect.right;
  let h = height - rect.top - rect.bottom;
  const current = w / h;

  if (current > aspect + ASPECT_TOLERANCE * aspect) {
    const newW = Math.round(h * aspect);
    left += Math.floor((w - newW) / 2);
    w = newW;
  } else if (current < aspect - ASPECT_TOLERANCE * aspect) {
    const newH = Math.round(w / aspect);
    top += Math.floor((h - newH) / 2);
    h = newH;
  }
  return { left, top, width: w, height: h };
}

async function main() {
  const meta = await sharp(inputPath).metadata();
  const { data, info } = await sharp(inputPath).greyscale().raw().toBuffer({ resolveWithObject: true });
  const bars = detectBars(data, info.width, info.height);
  const crop = coverCrop(bars, info.width, info.height, aspect);

  const barsFound = bars.top + bars.bottom + bars.left + bars.right > 0;
  const aspectOk = Math.abs(crop.width / crop.height - aspect) <= ASPECT_TOLERANCE * aspect;
  if (!barsFound && aspectOk) {
    await copyFile(inputPath, outputPath);
    console.log(JSON.stringify({ cropped: false, width: info.width, height: info.height, bars }));
    return;
  }

  let pipeline = sharp(inputPath).extract(crop);
  if (meta.format === "jpeg") pipeline = pipeline.jpeg({ quality: 92 });
  else if (meta.format === "webp") pipeline = pipeline.webp({ quality: 92 });
  else pipeline = pipeline.png();
  await pipeline.toFile(outputPath);

  console.log(JSON.stringify({ cropped: true, bars, crop, from: [info.width, info.height], to: [crop.width, crop.height] }));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err?.stack ?? String(err));
    process.exit(1);
  });
}
