// CLI: node image-lab-sheet.mjs <rows.json> <out.png>
// Task 7 Part 4 — one row per shot, columns = prompt variants (old | new).
// Each cell is labelled with its variant and prompt source.
import { readFile } from "node:fs/promises";
import sharp from "sharp";

const [rowsPath, outPath] = process.argv.slice(2);
const rows = JSON.parse(await readFile(rowsPath, "utf-8"));

const CELL_W = 480;
const CELL_H = 270;
const PAD = 8;
const LABEL_H = 26;

const groups = new Map();
for (const r of rows) {
  const key = `${r.topic}|${r.unit}`;
  if (!groups.has(key)) groups.set(key, {});
  groups.get(key)[r.variant] = r;
}
const variants = [...new Set(rows.map((r) => r.variant))];
const keys = [...groups.keys()];

const width = PAD + variants.length * (CELL_W + PAD);
const height = PAD + keys.length * (CELL_H + LABEL_H + PAD);
const composites = [];

for (let i = 0; i < keys.length; i++) {
  const group = groups.get(keys[i]);
  const first = Object.values(group)[0];
  const y = PAD + i * (CELL_H + LABEL_H + PAD);
  const label = `${first.topic.slice(0, 60)} · ${first.unit}`;
  composites.push({
    input: Buffer.from(`<svg width="${width}" height="${LABEL_H}"><text x="${PAD}" y="18" font-family="DejaVu Sans, Arial" font-size="15" fill="#222">${escapeXml(label)}</text></svg>`),
    top: y,
    left: 0,
  });
  for (let j = 0; j < variants.length; j++) {
    const cell = group[variants[j]];
    const x = PAD + j * (CELL_W + PAD);
    const tag = cell ? `${variants[j]} · ${cell.prompt_source} · ${cell.prompt_words}w · $${cell.cost_usd.toFixed(4)}` : `${variants[j]} · missing`;
    composites.push({
      input: Buffer.from(`<svg width="${CELL_W}" height="${LABEL_H}"><text x="2" y="18" font-family="DejaVu Sans, Arial" font-size="13" fill="#444">${escapeXml(tag)}</text></svg>`),
      top: y + LABEL_H - 6,
      left: x,
    });
    if (cell) {
      const img = await sharp(cell.file).resize(CELL_W, CELL_H, { fit: "cover" }).toBuffer();
      composites.push({ input: img, top: y + LABEL_H, left: x });
    }
  }
}

await sharp({ create: { width, height, channels: 3, background: "#ffffff" } })
  .composite(composites)
  .png()
  .toFile(outPath);
console.log(`wrote ${outPath} (${width}x${height})`);

function escapeXml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
