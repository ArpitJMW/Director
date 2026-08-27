# Architecture & Technical Decisions

Living document. Records how Clipify is actually built and why, deviating from or refining [`product.md`](product.md) where needed.

## System shape

```
                 ┌─────────────┐
   Browser  ───▶ │  apps/web   │  Next.js (SSR landing + client studio)
                 └──────┬──────┘
                        │  REST/JSON + JWT (Bearer)
                 ┌──────▼──────┐
                 │  apps/api   │  Rails 8 API-only
                 └──┬───┬───┬──┘
        PostgreSQL ◀─┘   │   └─▶ Redis ◀── Sidekiq workers
                         │                    │
                  Object storage (R2/S3) ◀────┘  generated media
                         ▲
                 ┌───────┴───────┐
                 │ apps/renderer │  Remotion (invoked by render jobs)
                 └───────────────┘
```

## Key decisions

### D1 — Monorepo with pnpm workspaces + Turborepo
Single repo per spec §45. JS side (`apps/web`, `apps/renderer`, `packages/*`) is a pnpm workspace; Turborepo orchestrates build/dev/lint/typecheck. Rails (`apps/api`) stays a standalone Bundler project — not a workspace member — but lives in the same repo.

### D2 — Rails API-only backend
`rails new --api`, PostgreSQL, Sidekiq + Redis for jobs. Rails 8 Solid Queue/Cache/Cable are **skipped** — the spec explicitly standardizes on Sidekiq + Redis (§12).

### D3 — Auth: Devise + JWT (`devise-jwt`)
Token-based auth. Rails issues a JWT on login/signup; the Next.js client sends it as `Authorization: Bearer <token>`. Chosen over Rails 8 native (cookie/session, awkward cross-origin) and hosted providers (vendor cost/lock-in). Revocation via a denylist strategy.

### D4 — API versioning under `/api/v1`
All application endpoints namespaced per spec §29. Non-versioned `/up` health check kept from Rails default.

### D5 — bigint PKs + `public_id` slugs
Integer primary keys internally; user-facing models expose a non-enumerable
`public_id` (`HasPublicId` concern) in the API and URLs. Chosen over plain
sequential IDs (enumeration) and UUID-everywhere (index size, ugly URLs).

### D6 — State machines via `aasm`
`Project`, `VideoRender`, `GenerationJob` use `aasm` with `no_direct_assignment`.
`Project` records `failed_from_status` so a failed run resumes at the stage that
failed (spec §28).

### D7 — Scene contract lives in two places, kept in sync
`Scene#to_scene_json` (Ruby) and `@clipify/video-schema` (Zod/TS) both implement
spec §19. Each has a test asserting the canonical shape. Changing the contract
means changing both.

### D8 — Controller hierarchy for authorization
`ApplicationController` (errors) → `Api::V1::BaseController` (JWT auth + Pundit
available, no enforced checks; used by `me`, `health`) → `Api::V1::ResourceController`
(`verify_authorized` on non-index, `verify_policy_scoped` on index — via `if:`
lambdas, not `only:/except:`, to dodge Rails 7.1's missing-callback-action raise).
Policies scope every read to `record.project.user_id == user.id`.

### D9 — Serializers are plain objects
`ApplicationSerializer` + one PORO per resource (`.call` / `.list`). No
serialization gem. Explicit, greppable, easy to shape per-endpoint with options
(`include_scenes:`, `include_script:`).

### D11 — Provider abstraction with an offline fake
Every external-model call goes through an adapter interface (`Providers::LLM::Base`).
`FakeAdapter` returns deterministic well-formed output so the whole pipeline runs
with no API key (default in dev/test). `AiGeneration.track!` wraps each call to
record status/tokens/cost/latency. Model default `claude-opus-5`, overridable via
`LLM_MODEL` for cost tuning once real cost data exists.

### D12 — Pipeline stages are Sidekiq jobs backed by GenerationJob rows
`Generation::BaseJob` + one subclass per stage. The `GenerationJob` row (own AASM)
tracks stage/attempts/status independently of the project, so one failed stage
never re-runs the whole project (spec §28). `sidekiq_retries_exhausted` marks the
project failed and records `failed_from_status` for resume.

### D10 — Frontend: JWT in an httpOnly cookie, proxied through Next
The browser never holds the token. Next route handlers (`/api/auth/*`) exchange
credentials for a cookie; `/api/v1/[...path]` transparently proxies data calls to
Rails with the cookie's bearer token. Client code calls same-origin `/api/v1/...`
via `apiFetch` + TanStack Query. `src/proxy.ts` (Next 16's renamed middleware)
does the UX-level auth redirect.

## Current build status

**Phase 2 — Foundation.**

- [x] Repo scaffold: git, monorepo dirs, pnpm/turbo config, docs
- [x] Rails API app scaffolded and booting (`apps/api`, module `Clipify`, Rails 8.1 API-only)
- [x] PostgreSQL connected (`clipify_development` / `clipify_test`), migrations green
- [x] Sidekiq + Redis wired (`config/sidekiq.yml` queues, `/sidekiq` dashboard in dev)
- [x] Devise + JWT auth: `POST /api/v1/auth/sign_up`, `sign_in`, `DELETE sign_out` (denylist revocation), `GET/PATCH /api/v1/me`
- [x] Readiness probe `GET /api/v1/health` (checks DB + Redis)
- [x] RSpec + FactoryBot + Faker; 34 examples green; RuboCop clean
- [x] Core V1 data model — 15 tables (spec §16), state machines (§18), Scene JSON contract (§19). See [`data-model.md`](data-model.md)
- [x] `@clipify/video-schema` package: Zod mirror of the Scene / storyboard / render-manifest contract
- [x] Seeds: 5 built-in templates (§24)
- [x] REST API for projects / scenes / templates / assets / renders / preflight (spec §29), Pundit authorization, serializers, pagy. Pipeline actions stubbed `501`. 51 request+model specs green. See [`api.md`](api.md)
- [x] Next.js shell (`apps/web`, :3001): Tailwind v4 + `@clipify/ui` primitives, TanStack Query, JWT-in-httpOnly-cookie via Next route handlers + `/api/v1` proxy. Landing / login / signup / dashboard / new project / project detail. Smoke-tested end-to-end (signup → cookie → proxy → create project → SSR dashboard → signout). See [`frontend.md`](frontend.md)
- [x] Shared packages: `@clipify/types` (API types), `@clipify/ui` (primitives + tokens)

**Phase 2 (Foundation) complete.**

**Phase 3 (AI pipeline) — in progress:**
- [x] Provider abstraction (`Providers::LLM::Base` + Anthropic + Fake adapters), `Providers::Pricing`, `AiGeneration.track!` ledger wrapper
- [x] Script generation: `Ai::ScriptService` (spec §22) + `Generation::ScriptJob` (Sidekiq, retryable) + `POST /projects/:id/script/generate` (202, idempotent) + `GET /projects/:id/jobs`
- [x] Storyboard + visual director: `Ai::ScenePlannerService` (§20 steps 7-9, §23) + `Generation::StoryboardJob` + `POST /projects/:id/storyboard/generate` — full-replace scenes following the §19 contract
- [x] Frontend: generate-script / generate-storyboard buttons, job polling (§30), script + scene display
- [ ] Research engine (§21), media stages (image/voice/caption/music)

See [`ai-pipeline.md`](ai-pipeline.md).

### Endpoints so far

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/up` | – | Liveness |
| GET | `/api/v1/health` | – | Readiness (DB + Redis) |
| POST | `/api/v1/auth/sign_up` | – | Register; returns JWT in `Authorization` header |
| POST | `/api/v1/auth/sign_in` | – | Login; returns JWT |
| DELETE | `/api/v1/auth/sign_out` | Bearer | Revoke current JWT |
| GET | `/api/v1/me` | Bearer | Current user |
| PATCH | `/api/v1/me` | Bearer | Update name |

## Deferred (not in the foundation step)

SaaS/billing tables (§16 "before public launch"), provider adapters (Phase 3), Remotion renderer (Phase 5), object storage integration (Phase 4).
