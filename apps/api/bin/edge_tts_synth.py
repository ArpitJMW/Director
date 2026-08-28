#!/usr/bin/env python3
"""Synthesize speech with Microsoft Edge TTS (free, no API key).

Usage:  echo "text" | edge_tts_synth.py <voice> <output.mp3>
Writes the MP3 to <output.mp3>; prints JSON to stdout:
  {"duration": <sec>, "words": [{"text": "...", "start": <sec>, "end": <sec>}, ...]}

Requires:  pip install edge-tts
"""
import asyncio
import json
import sys

try:
    import edge_tts
except ImportError:
    sys.stderr.write("edge-tts not installed. Run: pip install edge-tts\n")
    sys.exit(3)

TICKS_PER_SECOND = 10_000_000


async def synth(text: str, voice: str, out_path: str) -> dict:
    communicate = edge_tts.Communicate(text, voice)
    words = []
    with open(out_path, "wb") as audio:
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                start = chunk["offset"] / TICKS_PER_SECOND
                end = (chunk["offset"] + chunk["duration"]) / TICKS_PER_SECOND
                words.append({"text": chunk["text"], "start": round(start, 3), "end": round(end, 3)})

    duration = words[-1]["end"] if words else 0.0
    return {"duration": duration, "words": words}


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: edge_tts_synth.py <voice> <output.mp3>\n")
        return 2
    voice, out_path = sys.argv[1], sys.argv[2]
    text = sys.stdin.read().strip()
    if not text:
        sys.stderr.write("no text on stdin\n")
        return 2

    result = asyncio.run(synth(text, voice, out_path))
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
