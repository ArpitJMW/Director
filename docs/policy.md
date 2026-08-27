# Content Quality & Policy Engine

An **internal heuristic** (spec §6, §32) — never an official YouTube score and
never a monetization guarantee. Every report carries that disclaimer.

## Preflight report (`Policy::PreflightEngine`, spec §32)

`Generation::PreflightJob` (queue `policy`) → a `PreflightReport` row with a
verdict per check, a disclosure verdict, and a flat list of `{check, message}`
warnings.

| Check (`checks` key) | Checker | Basis |
| --- | --- | --- |
| `originality` | `Policy::OriginalityChecker` | LLM policy-analyst verdict on the script (pass/warn); `review` if the model output is unusable |
| `narrative_value` | `Policy::NarrativeValueChecker` | narration density (words/sec) + per-scene minimum (spec §6 — reject thin slideshows) |
| `repetition_risk` | `Policy::RepetitionChecker` | 3-word-shingle Jaccard vs the creator's recent completed videos + same-template streak (spec §33) |
| `asset_provenance` | `Policy::ProvenanceChecker` | every image scene has an asset; every asset has a `source_type`; narrated scenes have audio |
| `reuse_risk` | `Policy::ReuseChecker` | 8-word verbatim runs shared between narration and `source.raw_excerpt` (spec §21) |
| `copyright_license` | `Policy::CopyrightChecker` | licensed/stock assets and non-public-domain music carry a `license` string |
| `advertiser_suitability` | — | always `review` (spec §32) |

**AI disclosure** (`Policy::DisclosureChecker`, spec §7):
`required` (a realistic asset depicts a real person/event/place) ·
`review` (realistic AI-generated visuals present) ·
`not_required` (stylised/clearly synthetic).

**Final status** = `ready` only when every gating check is `pass`, disclosure is
`not_required`, and there are no warnings; otherwise `review_required`.

## Acknowledgement

`POST /api/v1/projects/:id/preflight/acknowledge` records
`acknowledged_at` / `acknowledged_by` (spec §31 — warnings must be *explicitly*
acknowledged before export).

## API

| Method | Path | |
| --- | --- | --- |
| POST | `/api/v1/projects/:id/preflight/generate` | run the engine (202 + job) |
| GET | `/api/v1/projects/:id/preflight` | latest report, or `204` |
| POST | `/api/v1/projects/:id/preflight/acknowledge` | acknowledge the latest report |

Frontend: `PreflightCard` on the project page — per-check badges, warnings, the
disclaimer, and an acknowledge button.

## Not built

`Policy::FactCheckService` (spec §14, §20 step 6), the full §31 objective QA pass
(generation-artifact detection, caption-sync verification, audio-level analysis),
and export gating (the report is shown but download isn't blocked yet).
