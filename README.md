# Clipify

AI video creation SaaS — turn a script or topic into a publish-ready video with a YouTube-oriented preflight report.

Full product & engineering spec: [`docs/product.md`](docs/product.md).

## Monorepo layout

| Path             | Stack                     | Purpose                                    |
| ---------------- | ------------------------- | ------------------------------------------ |
| `apps/api`       | Rails 8 (API-only)        | Core API, data model, Sidekiq pipeline     |
| `apps/web`       | Next.js + React + TS      | Landing site + authenticated studio        |
| `apps/renderer`  | Remotion                  | Programmatic React video rendering         |
| `packages/types` | TypeScript                | Shared API + domain types                  |
| `packages/video-schema` | TypeScript + Zod   | Scene JSON / render manifest contract      |
| `packages/ui`    | React                     | Shared design-system primitives            |
| `packages/prompts` | TS                      | Versioned LLM prompt templates             |

The Rails app manages its own gems with Bundler. Everything JS is a pnpm workspace driven by Turborepo.

## Prerequisites

- Ruby 3.4.x, Rails 8.1.x, Bundler
- Node 24.x, pnpm 11.x (`corepack enable`)
- PostgreSQL 18, Redis 8
- FFmpeg (needed once the render pipeline lands)

## Getting started

```bash
# JS workspaces
pnpm install

# Rails API (terminal 1)
cd apps/api
bundle install
bin/rails db:prepare      # create + migrate + seed
bin/rails server          # http://localhost:3000
bundle exec sidekiq       # background jobs (terminal 2)

# Next.js web app (terminal 3)
pnpm --filter @clipify/web dev   # http://localhost:3001
```

Whole JS workspace: `pnpm turbo run typecheck lint test`. Rails tests: `cd apps/api && bundle exec rspec`.

## Documentation

| Doc | Contents |
| --- | --- |
| [`docs/product.md`](docs/product.md) | Master spec (source of truth) |
| [`docs/architecture.md`](docs/architecture.md) | System design & key technical decisions |
| [`docs/data-model.md`](docs/data-model.md) | Core schema, state machines, Scene contract |
| [`docs/api.md`](docs/api.md) | REST API reference |
| [`docs/frontend.md`](docs/frontend.md) | Next.js app — auth, data layer, routes |
| [`docs/ai-pipeline.md`](docs/ai-pipeline.md) | Provider abstraction, script generation, job lifecycle |
| [`docs/storage.md`](docs/storage.md) | Object storage adapters, `Asset.store!`, signed URLs |
| `docs/video-engine.md` | Remotion compositions & templates _(tbd)_ |
| `docs/policy.md` | Quality & YouTube preflight engine _(tbd)_ |
| `docs/runbook.md` | Ops / on-call _(tbd)_ |

## Build status

**Phase 2 (Foundation) — complete.** **Phase 3 (AI pipeline) — in progress:**
provider abstraction + script generation are live (`POST
/projects/:id/script/generate`). Storyboard / media stages next. See
[`docs/architecture.md`](docs/architecture.md).
