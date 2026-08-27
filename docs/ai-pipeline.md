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

**Selection:** `LLM_PROVIDER` env (`anthropic` | `fake`). Defaults to `anthropic`
when `ANTHROPIC_API_KEY` is set, otherwise `fake` — so the pipeline runs offline
with no key. Tests always use `FakeAdapter` (`spec/support/providers.rb`).

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
| GET | `/api/v1/projects/:id/jobs` | `{ jobs: [...] }` (newest first; `?active=true` to filter) |

Frontend: `useGenerateScript` + `useProjectJobs` (polls every 2s while a job is
active); the project detail page shows the generated script when
`project.current_script` is present.

## Not yet built

Research engine (§21), storyboard / scene planner (§20 steps 7-9), visual
director (§23), fact-check, and every media stage. `generate_storyboard`,
`render`, `regenerate_scene`, `regenerate_scene_asset` still return `501`.
