# Data Model

The core V1 schema (spec §16–§19). SaaS/billing tables (`plans`, `subscriptions`,
`credit_transactions`, `usage_records`, `payments`, `organizations`,
`team_members`, `api_keys`) are deliberately **not** built yet — spec §16 places
them "before public launch" (Phase 9).

## Conventions

- **Primary keys:** `bigint`. User-facing models also carry a `public_id`
  (`HasPublicId` concern) — a non-enumerable slug like `proj_f8k2p9qd4m` used in
  the API and URLs. Prefixes: `user_`, `proj_`, `scr_`, `src_`, `scn_`, `ast_`,
  `vox_`, `mus_`, `rnd_`, `gen_`, `job_`, `pfl_`, `tpl_`, `tplv_`.
- **Money:** provider/infra costs are `decimal(12,6)` USD columns named `cost_usd`.
  Credits (spec §34) are a separate later concern.
- **Enums:** stored as plain strings, validated in the model against a frozen
  constant (e.g. `Scene::VISUAL_TYPES`). Allowed values are also noted in each
  migration.
- **State machines:** `aasm` on `Project`, `VideoRender`, `GenerationJob`, with
  `no_direct_assignment` so `status` only changes through events.
- **JSON:** `jsonb` columns for flexible/nested data (`settings`, `metadata`,
  `config`, `manifest`, `alignment`, `checks`, …), always `null: false` with a
  `{}`/`[]` default.

## Entities

```
User
 └── Project ...................... lifecycle state machine (spec §18)
      ├── Script (versioned, one `current`)
      │    └── claims → Source
      ├── Source ................... facts kept separate from interpretation (§21)
      ├── Scene (ordered) .......... the Scene JSON contract (§19)
      │    ├── Asset (many; one `selected_asset`)
      │    └── VoiceGeneration
      ├── Asset ................... provenance + AI-disclosure flags (§6, §7, §27)
      ├── VoiceGeneration ......... TTS + alignment for captions (§26)
      ├── MusicTrack ............. (project-scoped or shared library)
      ├── VideoRender ............ render manifest → MP4, state machine (§28)
      ├── AiGeneration ........... provider-call ledger: cost/tokens/latency (§37)
      ├── GenerationJob ......... retryable pipeline unit, idempotency key (§20, §28)
      ├── GenerationLog ......... append-only structured log lines
      └── PreflightReport ....... YouTube preflight, heuristic only (§32)

Template
 └── TemplateVersion (config = design language, spec §24)
```

### Project lifecycle (spec §18)

```
draft
 → researching → script_generating → storyboarding → generating_assets
 → generating_voice → generating_captions → rendering → quality_check → completed

any working state → failed        (remembers failed_from_status)
failed            → resume        (returns to the stage that failed)
non-terminal      → cancelled
failed | cancelled → reset_to_draft
```

Events: `start_research!`, `start_script!`, `start_storyboard!`, `start_assets!`,
`start_voice!`, `start_captions!`, `start_render!`, `start_quality_check!`,
`complete!`, `mark_failed!`, `resume!`, `cancel!`, `reset_to_draft!`.

### Scene JSON contract (spec §19)

`Scene#to_scene_json` is the canonical Ruby side. The TypeScript mirror is
`@clipify/video-schema` (`packages/video-schema`) — a Zod schema consumed by the
renderer. **These two must stay in lockstep.** Shape:

```json
{
  "id": "scene_01",
  "duration": 7,
  "narration": "...",
  "visual_type": "image",
  "visual_prompt": "...",
  "asset_id": "ast_...",
  "caption": "...",
  "animation": "ken_burns",
  "transition": "fade",
  "background_music_level": 0.15
}
```

`packages/video-schema` also defines `StoryboardSchema` and
`RenderManifestSchema` (the fully-resolved storyboard + template + audio the
renderer needs, spec §20 step 14).

## Circular foreign keys

- `scenes.selected_asset_id → assets.id` and `assets.scene_id → scenes.id`:
  assets carry the real FK; `selected_asset_id` gets its FK in the
  `create_assets` migration, `on_delete: :nullify`.
- `templates.latest_version_id → template_versions.id` and
  `template_versions.template_id → templates.id`: FK added after both tables
  exist.

## Seeds

`bin/rails db:seed` is idempotent and creates the five built-in templates from
spec §24: Dark Documentary, Modern Tech, Historical Documentary, Cartoon
Explainer, Minimal Educational — each with a published `TemplateVersion` whose
`config` holds typography / colors / caption / animation / transition / audio
rules / scene presets / thumbnail style.
