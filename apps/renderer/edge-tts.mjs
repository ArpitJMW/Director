// Microsoft Edge TTS (free, no API key). The Rails EdgeTtsAdapter shells out:
//   echo "text" | node edge-tts.mjs <voice> <output.mp3>
// Writes the MP3; prints JSON to stdout:
//   {"duration": <sec>, "words": [{"text": "...", "start": <sec>, "end": <sec>}]}

import { createWriteStream, readFileSync } from "node:fs";
import { MsEdgeTTS, OUTPUT_FORMAT } from "msedge-tts";

const TICKS_PER_SECOND = 10_000_000;

async function main() {
  const [voice, outPath] = process.argv.slice(2);
  if (!voice || !outPath) {
    console.error("usage: node edge-tts.mjs <voice> <output.mp3>");
    process.exit(2);
  }
  const text = readFileSync(0, "utf-8").trim();
  if (!text) {
    console.error("no text on stdin");
    process.exit(2);
  }

  const tts = new MsEdgeTTS();
  await tts.setMetadata(voice, OUTPUT_FORMAT.AUDIO_24KHZ_48KBITRATE_MONO_MP3, {
    wordBoundaryEnabled: true,
  });

  const { audioStream, metadataStream } = await tts.toStream(text);
  const words = [];

  metadataStream.on("data", (raw) => {
    const payload = Buffer.isBuffer(raw) ? JSON.parse(raw.toString()) : raw;
    for (const entry of payload.Metadata ?? []) {
      if (entry.Type !== "WordBoundary") continue;
      const start = entry.Data.Offset / TICKS_PER_SECOND;
      const end = (entry.Data.Offset + entry.Data.Duration) / TICKS_PER_SECOND;
      words.push({
        text: entry.Data.text.Text,
        start: Number(start.toFixed(3)),
        end: Number(end.toFixed(3)),
      });
    }
  });

  await new Promise((resolve, reject) => {
    const file = createWriteStream(outPath);
    audioStream.pipe(file);
    audioStream.on("error", reject);
    file.on("error", reject);
    file.on("finish", resolve);
  });

  const duration = words.length ? words[words.length - 1].end : 0;
  console.log(JSON.stringify({ duration, words }));
}

main().catch((err) => {
  console.error(err?.stack ?? String(err));
  process.exit(1);
});
