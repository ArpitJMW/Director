# AI Providers — setup & cost

Every external model call goes through an adapter interface (spec §15). Each
layer picks its provider from an env var, else auto-detects from which key is
present, else falls back to the deterministic **`fake`** adapter (so the whole
pipeline runs offline).

| Layer | `*_PROVIDER` values | auto-detect key |
| --- | --- | --- |
| LLM (script, storyboard, preflight) | `gemini` · `anthropic` · `fake` | `GEMINI_API_KEY` → `ANTHROPIC_API_KEY` |
| Images (one per scene) | `cloudflare` · `gemini` · `fake` | `CLOUDFLARE_API_TOKEN` → `GEMINI_API_KEY` |
| Voice (narration + timing) | `edge_tts` · `elevenlabs` · `fake` | `ELEVENLABS_API_KEY` (edge_tts is opt-in only) |
| Render | Remotion, local | — (no API) |

There is **no AI-video-generation cost** — the video is composited locally by
Remotion from images + Ken Burns + narration.

## Free stack ($0 / video)

```dotenv
# apps/api/.env
LLM_PROVIDER=gemini
LLM_MODEL=gemini-2.5-flash
GEMINI_API_KEY=...                 # https://aistudio.google.com/apikey

IMAGE_PROVIDER=cloudflare
CLOUDFLARE_ACCOUNT_ID=...          # dash.cloudflare.com → AI → Workers AI
CLOUDFLARE_API_TOKEN=...           # create a token with "Workers AI" permission

VOICE_PROVIDER=edge_tts
EDGE_TTS_VOICE=en-US-AriaNeural
```

No extra installs — the edge-tts helper is Node (`apps/renderer/edge-tts.mjs`,
`msedge-tts`), pulled in by `pnpm install`. Just restart Rails + Sidekiq.

**Free-tier limits:** Gemini 2.5 Flash ≈ 250 requests/day; Cloudflare Workers AI
≈ 10,000 neurons/day (~hundreds of FLUX images); edge-tts unlimited.
**Commercial note:** edge-tts and ElevenLabs' free tier don't grant commercial
rights — fine for validation, revisit before monetising.

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
