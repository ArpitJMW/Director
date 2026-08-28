# AI Providers — setup & cost

Every external model call goes through an adapter interface (spec §15). Each
layer picks its provider from an env var, else auto-detects from which key is
present, else falls back to the deterministic **`fake`** adapter (so the whole
pipeline runs offline).

| Layer | `*_PROVIDER` values | auto-detect key |
| --- | --- | --- |
| LLM (script, storyboard, preflight) | `groq` · `gemini` · `anthropic` · `fake` | `GROQ_API_KEY` → `ANTHROPIC_API_KEY` → `GEMINI_API_KEY` |
| Images (one per scene) | `pollinations` · `cloudflare` · `gemini` · `fake` | `CLOUDFLARE_API_TOKEN`; `gemini` needs `GEMINI_IMAGE_ENABLED=1`; `pollinations` is opt-in |
| Voice (narration + timing) | `gemini_tts` · `edge_tts` · `elevenlabs` · `fake` | `ELEVENLABS_API_KEY` (gemini_tts / edge_tts are opt-in only) |
| Render | Remotion, local | — (no API) |

There is **no AI-video-generation cost** — the video is composited locally by
Remotion from images + Ken Burns + narration.

## Free stack ($0 / video) — verified working

```dotenv
# apps/api/.env
LLM_PROVIDER=groq
LLM_MODEL=openai/gpt-oss-120b
GROQ_API_KEY=...                   # https://console.groq.com/keys  (no card)

IMAGE_PROVIDER=pollinations        # https://pollinations.ai  (no key at all)
IMAGE_MODEL=flux

VOICE_PROVIDER=gemini_tts          # Gemini TTS — needs GEMINI_API_KEY (below)
GEMINI_API_KEY=...                 # https://aistudio.google.com/apikey
GEMINI_TTS_VOICE=Charon            # Charon | Kore | Puck | Aoede | Fenrir | ...
```

**Voice options, in order of preference for the free stack:**
- `gemini_tts` — Gemini TTS. Works on a plain Gemini key even though *image*
  generation on the same key is quota-limited. Multilingual (handles
  Hindi/Hinglish). No word timing from the API, so captions are evenly spaced.
- `edge_tts` — Microsoft Edge TTS via `apps/renderer/edge-tts.mjs` (`msedge-tts`,
  from `pnpm install`). Best word-level timing, but its WebSocket to Microsoft
  is **blocked on some ISPs/networks** — if narration jobs fail with
  "Connect Error", switch to `gemini_tts`.
- `elevenlabs` — needs a paid plan (free tier can't use API voices).

**Free-tier limits:** Groq ≈ 14,400 requests/day (a video ≈ 5 calls);
Pollinations is rate-limited under load (set `POLLINATIONS_TOKEN` for more);
edge-tts unlimited.
**Commercial note:** edge-tts and Groq's free tier don't grant broad commercial
rights — fine for validation, revisit before monetising.

**Alternatives that also work free** (need a bit more setup):
Cloudflare Workers AI FLUX (`IMAGE_PROVIDER=cloudflare`, needs
`CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_API_TOKEN`); Gemini text
(`LLM_PROVIDER=gemini`, `LLM_MODEL=gemini-3.6-flash`, `GEMINI_API_KEY`).

## Paid options (better quality)

| Layer | Service | ~Cost per video (6 scenes, ~150 words) |
| --- | --- | --- |
| LLM | `claude-haiku-4-5` / `claude-sonnet-5` (`LLM_PROVIDER=anthropic`) | $0.01–0.05 |
| Images | Gemini Flash Image "Nano Banana" (`IMAGE_PROVIDER=gemini`, `IMAGE_MODEL=gemini-2.5-flash-image`) | $0.20–0.40 |
| Voice | ElevenLabs (`ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`) | $0.70–1.50 (free tier: 10k chars/mo) |

Costs land in the `ai_generations` ledger (`cost_usd` per call) — the source for
the eventual credit/pricing model (spec §34/§35).

## How each adapter works

- **`Providers::LLM::GeminiAdapter`** — `POST …:generateContent`,
  `responseMimeType: application/json` (all current LLM uses want JSON).
- **`Providers::Image::CloudflareAdapter`** — `POST …/ai/run/@cf/…/flux-1-schnell`,
  `steps: 4`. FLUX schnell outputs 1024×1024; the renderer crops to the target
  aspect ratio.
- **`Providers::Voice::EdgeTtsAdapter`** — shells out to
  `node apps/renderer/edge-tts.mjs <voice> <out.mp3>` (text on stdin;
  `EDGE_TTS_COMMAND` overrides), which streams audio + `WordBoundary` events and
  prints `{duration, words:[{text,start,end}]}`. `Media::CaptionService` accepts
  this word-level shape directly.
