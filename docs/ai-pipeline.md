# AI Pipeline

The pipeline (spec §20) runs as retryable Sidekiq stages. Each stage is driven by
a `GenerationJob` row; each provider call is recorded in `ai_generations` with
cost/tokens/latency (spec §37).

## Provider abstraction (spec §15)

```
Providers.llm                      -> the configured LLM adapter
  Providers::LLM::Base             -> #chat(system:, messages:, max_tokens:, model:) -> Result
  Providers::LLM::AnthropicAdapter -> anthropic gem, model from LLM_MODEL (default claude-opus-5)
  Providers::LLM::FakeAdapter      -> deterministic offline output for dev/test
```

`Providers::LLM::Result` is `{ text, model, provider, stop_reason, usage:{input_tokens,output_tokens}, provider_request_id, raw }`.

**Selection:** `LLM_PROVIDER` env (`gemini` | `anthropic` | `fake`); auto-detects
from whichever key is present, else `fake` — so the pipeline runs offline with no
key. Tests always use `FakeAdapter` (`spec/support/providers.rb`). Full provider
setup + cost table: [`providers.md`](providers.md).

**Cost:** `Providers::Pricing.cost_usd` — a per-model USD/1M-token table.

**Model default is `claude-opus-5`.** Set `LLM_MODEL=claude-sonnet-5` (or
`claude-haiku-4-5`) to trade quality for cost once you have real cost data
(spec §35).

## `AiGeneration.track!`

```ruby
AiGeneration.track!(project:, kind:, provider:, model:, request:) do |generation|
  Providers.llm.chat(system:, messages:)   # returns Result
end
```

Creates the ledger row (`running`), times the call, on success records tokens +
`Pricing.cost_usd` + a `generation_logs` line and marks it `succeeded`; on error
marks it `failed`, logs, and re-raises.

## Stages implemented

### Script (`Generation::ScriptJob`, queue `script`)

`Ai::ScriptService` (spec §22): builds a system + user prompt from the project
(topic, niche, audience, duration, tone, creator instructions, research sources),
calls the LLM asking for a strict JSON object, parses it, and creates the new
**current** `Script` (`source_type: ai_generated`, linked `ai_generation`).
Fields: `title_options`, `selected_title`, `hook`, `story_angle`, `sections`,
`full_narration`, `estimated_duration_seconds`, `creative_notes`, `claims`.

Bad/unparseable JSON marks the generation `failed` and raises
`Ai::ScriptService::Error`.

### Storyboard + Visual Director (`Generation::StoryboardJob`, queue `storyboard`)

`Ai::ScenePlannerService` (spec §20 steps 7-9, §23). Takes `project.current_script`,
asks the LLM to split the narration into scenes and — acting as visual director —
pick the most useful `visual_type` per beat (deliberately varied, *not* one image
per sentence). Full-replace: `project.scenes.destroy_all` then recreate in order,
each following the Scene JSON contract (§19), with enum values coerced to the
allowed sets and durations/levels clamped. Records a `scene_plan` ai_generation.

Requires a current script — otherwise `409 { message: "Generate a script first." }`.

### Images (`Generation::AssetsJob`, queue `media`)

`Media::ImageGenerationService` (spec §14, §20 step 10). For each scene whose
`visual_type` is image-like (`image`, `split_screen`) it calls
`Providers.image.generate(prompt: scene.visual_prompt, aspect_ratio:)`, stores the
result via `Asset.store!` (`source_type: ai_generated`), and sets
`scene.selected_asset` + `scene.status = "ready"`. Other visual types (chart,
timeline, quote_card, …) are skipped for later stages.

- **Provider** (`Providers::Image::Base`): `GeminiAdapter` (Nano Banana, raw REST,
  untested live) + `FakeImageAdapter` (pure-Ruby ChunkyPNG gradient at the right
  dimensions — offline default).
- **Per-scene failures don't abort the batch** (spec §28); `AssetsJob` collects
  them, logs each, and re-raises at the end so Sidekiq retries — and ready scenes
  are skipped on the retry.
- `Generation::SceneAssetJob` regenerates one scene's image and destroys the
  superseded asset (storage object purged by an `Asset` `after_destroy_commit`).
- Image cost comes from `Providers::Pricing.image_cost_usd` (flat per image) and
  is carried on the `Result`, not derived from tokens.

### Voice + captions (`Generation::VoiceJob`, queue `media`)

`Media::VoiceGenerationService` (spec §14, §20 steps 11-12, §26). Per scene with
narration: `Providers.voice.synthesize` → stores an `audio` asset → derives timed
caption cues from the character alignment (`Media::CaptionService`) → creates a
`VoiceGeneration` (audio_asset, `alignment`, `captions`, duration, cost) and
supersedes any earlier one for that scene. Voice id from
`project.settings["voice_id"]` or the provider default.

- **Provider** (`Providers::Voice::Base`): `ElevenLabsAdapter` (`/with-timestamps`,
  raw REST, untested live) + `FakeVoiceAdapter` (silent WAV sized to the text +
  synthetic even alignment — offline default).
- **`Media::CaptionService`** groups words (≤7 words / ≤2.6s per cue) using word
  boundaries from the alignment; falls back to one untimed cue if alignment is
  missing.
- `VoiceJob` isolates per-scene failures and skips scenes already narrated with
  the same text on retry.
- `SceneSerializer` exposes `narration_audio {url,duration,provider}` and
  `captions[]` for the renderer.

## Job lifecycle (spec §28)

```
controller: create GenerationJob (pending)
          -> project.start_script!
          -> job.enqueue! (queued)
          -> ScriptJob.perform_async(job.id)

worker:  Generation::BaseJob#perform
          -> return if job succeeded/cancelled   (idempotent)
          -> job.start! (running, attempts++)
          -> subclass #run
          -> job.succeed!
         on error: log + record + re-raise -> Sidekiq retries (3x)
         sidekiq_retries_exhausted -> job.mark_failed! + project.mark_failed!
                                      (project remembers failed_from_status)
```

Duplicate `POST .../script/generate` while a job is `active` returns the existing
job (202), never a second job.

## API

| Method | Path | Result |
| --- | --- | --- |
| POST | `/api/v1/projects/:id/script/generate` | `202 { job, project }`, or `409 invalid_state`, or `403` |
| POST | `/api/v1/projects/:id/storyboard/generate` | `202 { job, project }`, or `409` (no script / bad state), or `403` |
| POST | `/api/v1/projects/:id/assets/generate` | `202` — generate images for all scenes, or `409` (no storyboard) |
| POST | `/api/v1/projects/:id/voice/generate` | `202` — narrate + caption every scene, or `409` |
| POST | `/api/v1/scenes/:id/assets/regenerate` | `202` — regenerate one scene's image |
| GET | `/api/v1/projects/:id/jobs` | `{ jobs: [...] }` (newest first; `?active=true` to filter) |

Frontend: `useGenerateScript` / `useGenerateStoryboard` + `useProjectJobs` (polls
every 2s while a job is active). The project detail page shows the script and the
scene list, and invalidates both when a job finishes.

## Not yet built

Research engine (§21), fact-check (§20 step 6), non-image visual types
(charts/timelines/quote cards), music, and the render. `render` and
`regenerate_scene` (full scene re-plan) still return `501`.
