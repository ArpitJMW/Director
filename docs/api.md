# API Reference

Base URL: `/api/v1`. JSON only. All resource ids in URLs and payloads are
`public_id` slugs (`proj_…`, `scn_…`, `tpl_…`), never integer PKs.

## Authentication

Devise + JWT. The token is returned in the **`Authorization` response header**
on sign-up / sign-in and must be sent back as `Authorization: Bearer <token>`.

| Method | Path | Body | Notes |
| --- | --- | --- | --- |
| POST | `/auth/sign_up` | `{ user: { name, email, password } }` | 201, token in header |
| POST | `/auth/sign_in` | `{ user: { email, password } }` | 200, token in header |
| DELETE | `/auth/sign_out` | – | Bearer; revokes the presented token (denylist) |
| GET | `/me` | – | Bearer; current user |
| PATCH | `/me` | `{ user: { name } }` | Bearer |

## Health

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/up` | Liveness (Rails default), not under `/api/v1` |
| GET | `/api/v1/health` | Readiness — checks Postgres + Redis, `503` if degraded |

## Projects

| Method | Path | Body | Result |
| --- | --- | --- | --- |
| GET | `/projects` | – | `{ projects: [...] }`, paginated (`X-Total-Count`, `X-Page`, `X-Total-Pages`); `?page=`, `?per_page=` |
| POST | `/projects` | `{ project: { title, topic, format, aspect_ratio, niche, audience, tone, target_duration_seconds, creator_instructions, research_enabled, template_id, settings } }` | `201 { project }` |
| GET | `/projects/:id` | – | `{ project }` including `scenes` and `current_script` |
| PATCH | `/projects/:id` | `{ project: {...} }` | `{ project }` |
| DELETE | `/projects/:id` | – | `204` |
| GET | `/projects/:id/preflight` | – | `{ preflight }` — latest report, or `204` if none |
| GET | `/projects/:id/scenes` | – | `{ scenes: [...] }` ordered by position |
| GET | `/projects/:id/renders` | – | `{ renders: [...] }` newest version first |

`status` follows the lifecycle state machine (spec §18): `draft`, `researching`,
`script_generating`, `storyboarding`, `generating_assets`, `generating_voice`,
`generating_captions`, `rendering`, `quality_check`, `completed`, `failed`,
`cancelled`.

## Scenes

| Method | Path | Body | Result |
| --- | --- | --- | --- |
| GET | `/scenes/:id` | – | `{ scene }` |
| PATCH | `/scenes/:id` | `{ scene: { narration, visual_type, visual_prompt, caption, animation, transition, duration_seconds, background_music_level, notes } }` | `{ scene }` — creator corrections only |

Each scene serializes as `{ id, project_id, status, position, notes, scene: <§19 contract>, selected_asset }`.

## Templates

| Method | Path | Result |
| --- | --- | --- |
| GET | `/templates` | `{ templates: [...] }` — published + those you own |
| GET | `/templates/:id` | `{ template }` with `latest_version.config` |

## Assets

| Method | Path | Result |
| --- | --- | --- |
| GET | `/assets?project_id=&type=` | `{ assets: [...] }`, paginated; scoped to your projects |

## Pipeline actions — **not implemented yet** (Phase 3+)

These endpoints exist and enforce ownership, but return
`501 { error: "not_implemented", available_in: "Phase 3 — AI pipeline" }`:

| Method | Path |
| --- | --- |
| POST | `/projects/:id/script/generate` |
| POST | `/projects/:id/storyboard/generate` |
| POST | `/projects/:id/render` |
| POST | `/scenes/:id/regenerate` |
| POST | `/scenes/:id/assets/regenerate` |

## Errors

| Status | Body |
| --- | --- |
| 401 | (empty) — missing/invalid/revoked token |
| 403 | `{ error: "forbidden" }` — not your resource |
| 404 | `{ error: "not_found", message }` |
| 422 | `{ error: "unprocessable_content", messages: [...] }` |
| 501 | `{ error: "not_implemented", message, available_in }` |
