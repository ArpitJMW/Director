# Clipify — Master Product & Engineering Specification

> From Product Vision → AI Pipeline → Video Engine → YouTube-Safe Preflight → SaaS Launch
>
> **Document status:** Master planning document · **Version:** 1.0 · **Date:** August 2026
>
> **Primary goal:** Build a production-quality AI video creation platform, validate it through our own YouTube content, then launch it as a subscription/credit-based SaaS.

_This file is the verbatim source-of-truth specification. Engineering docs derived from it live alongside it in `docs/`._

---

## 1. Executive Summary

The product is an AI-powered creative studio for faceless video creators. A user supplies an idea, topic, outline, or complete script; the system can research the topic, create or improve a script, plan scenes, choose visual treatments, generate assets, create narration and captions, assemble the project using reusable design systems, render a final video, and provide a YouTube-oriented preflight report.

The product is not intended to be a mass-production button. Its core differentiation is creator-controlled, original, well-researched, visually diverse content. Templates control visual identity, but the system should not force every video into the same story/scene pattern.

## 2. Product Vision

**North-star statement:** Turn a creator's idea or script into a high-quality, publish-ready video while dramatically reducing manual production work.

## 3. Target Customers

- **Primary:** faceless YouTube creators.
- **Secondary:** Shorts/Reels creators, educators, marketers, agencies, small media teams.
- **Later:** businesses, teams, enterprise content departments, API customers.

## 4. V1 Scope

The first working product must do one thing end-to-end:

```
Paste script/topic
  ↓
Choose video format + template
  ↓
Generate storyboard
  ↓
Generate visuals
  ↓
Generate voice
  ↓
Generate captions
  ↓
Render
  ↓
Preview/download MP4
```

Initial target: reliable 60–180 second videos. Do not start with 10–20 minute documentary generation.

## 5. Product Principles

- **Originality first:** the final video must contain substantive creative, educational, or entertainment value.
- **Creator control:** AI assists; the user can edit/regenerate scenes and assets.
- **Template ≠ repeated content:** templates define visual identity, not identical story structure.
- **Provider abstraction:** never hard-code the entire product around one AI vendor.
- Every long-running operation is asynchronous and retryable.
- Every generated asset has provenance, usage metadata, and cost tracking.
- **Quality before scale:** validate with our own content before public launch.
- No guarantee of YouTube monetization; the product provides policy-aware checks only.

## 6. YouTube Policy-Aware Product Requirements

YouTube's current official monetization guidance says monetized content should be original and authentic, and not mass-produced, generic, repetitive, or made primarily to obtain views. Its current "inauthentic content" guidance specifically flags repetitive/mass-produced videos, templated storylines with minimal variation, low-value slideshows, and generic AI-generated content that appears mass-produced. YouTube also says AI tools can be used and that content can remain eligible when it provides original value.

The product therefore includes a **Content Quality & Policy Engine**. It is an internal heuristic, not an official YouTube score and not a monetization guarantee.

- **Originality check:** identify generic or overly derivative scripts/storylines.
- **Repetition check:** compare new projects against the creator's previous videos.
- **Narrative-value check:** reject image-only/slideshow outputs with weak narration or educational/entertainment value.
- **Asset provenance:** record whether each asset is AI-generated, user-provided, licensed, public-domain, or another permitted source.
- **AI disclosure check:** flag realistic synthetic/altered content that may require YouTube disclosure.
- **Reuse check:** avoid workflows that simply copy articles, news feeds, YouTube videos, or other creators' material without substantive transformation.
- **Export preflight:** show warnings before the final video is downloaded.

## 7. AI Disclosure Handling

YouTube currently requires disclosure when AI meaningfully alters or generates content that appears photorealistic, including making a real person appear to say/do something they did not, altering real events/places, or generating realistic scenes that did not occur. Production assistance such as scripts, outlines, thumbnails, captions and similar assistance generally does not require disclosure by itself. YouTube states that disclosure itself does not reduce monetization eligibility.

Every asset/project should therefore carry metadata such as: `ai_generated`, `realistic`, `represents_real_person`, `represents_real_event_or_place`, `provider`, `requires_disclosure`, `source_type`, `license/provenance`.

## 8. User Journey

```
Landing Page → Sign up / Login → Dashboard → Create Video → Choose format
  → Enter topic / paste script / outline → Choose template + voice + duration
  → Research (optional) → Script / storyboard → Review → Generate assets
  → Editor / scene corrections → Render → YouTube preflight → Export
```

## 9. Frontend — Recommended Stack

- Next.js + React + TypeScript.
- A component-based design system with reusable primitives.
- Server-side/public pages where useful; authenticated app as a client-rich studio.
- API communication with Rails through a typed API client.
- WebSocket/SSE or polling for generation progress initially; upgrade as needed.
- Figma for product design and design-system source of truth.

## 10. Frontend Application Areas

- **Landing page:** hero, workflow, showcase, templates, pricing, FAQ, CTA.
- **Authentication:** sign up, login, password reset, optional social login later.
- **Dashboard:** projects, recent videos, credits, generation status, quick-create.
- **Create Video wizard:** format, topic/script, niche, duration, template, voice, advanced options.
- **Script editor:** editable AI output, source references, outline/angle controls.
- **Storyboard editor:** scene cards, narration, visual prompt, duration, asset, caption, animation.
- **Video editor:** preview, scene list, timeline, regenerate/replace controls.
- **Asset library:** images, videos, audio, music, logos, reusable assets.
- **Templates:** browse, preview, select, save brand defaults.
- **Brand kit:** logo, fonts, colors, intro/outro, caption style.
- **Render screen:** job progress, logs/status, estimated stages, retry.
- **Export/history:** final renders, versions, download/share.
- **Credits/billing:** plan, remaining credits, transaction history, invoices.
- **Settings:** profile, security, API/provider preferences where applicable.

## 11. Core Frontend Components

AppShell, Sidebar, TopBar, Button / Input / Select / Modal, ProjectCard, ProjectStatus, CreateVideoWizard, ScriptEditor, SourceList, StoryboardSceneCard, SceneInspector, AssetPicker, AssetPreview, VideoPlayer, Timeline, TemplateCard, TemplatePreview, VoiceSelector, GenerationProgress, PreflightReport, CreditBalance, BillingPanel, NotificationCenter.

## 12. Backend — Recommended Stack

- Ruby on Rails API because the existing development skillset includes Rails.
- PostgreSQL for application data.
- Redis for queues/caching/temporary coordination.
- Sidekiq for background jobs.
- Object storage such as Cloudflare R2 or Amazon S3 for generated media.
- Remotion for programmatic React-based video composition/rendering.
- FFmpeg for media processing where required.
- Provider adapters for LLM, image, voice, music and future video providers.

## 13. Backend Architecture

```
Next.js
  │  REST/JSON
  ▼
Rails API
  ├── PostgreSQL
  ├── Redis
  ├── Sidekiq
  └── Object Storage → Generated media

Sidekiq
  ├── Research jobs
  ├── Script jobs
  ├── Storyboard jobs
  ├── Image jobs
  ├── Voice jobs
  ├── Caption jobs
  ├── Render jobs
  └── Quality/preflight jobs
```

## 14. Backend Service Boundaries

```
app/services/
  ai/
    research_service
    script_service
    scene_planner
    visual_director
    fact_check_service
  media/
    image_generation_service
    voice_generation_service
    music_service
    caption_service
  video/
    storyboard_builder
    render_video
    media_processor
    thumbnail_generator
  policy/
    originality_checker
    repetition_checker
    disclosure_checker
    provenance_checker
    youtube_preflight
  billing/
    credit_service
    usage_meter
    subscription_service
```

## 15. Provider Abstraction

Use interfaces/adapters so the application can change vendors without rewriting business logic.

```
LLMProvider    ├── Claude   ├── Gemini   └── future providers
ImageProvider  ├── Gemini / Nano Banana   └── future providers
VoiceProvider  ├── ElevenLabs   └── future providers
VideoProvider  ├── Remotion/FFmpeg renderer   └── future providers
```

## 16. Database Model

**Initial entities:** users, projects, scripts, sources, scenes, assets, voice_generations, music_tracks, video_renders, templates, template_versions, ai_generations, generation_jobs, generation_logs.

**SaaS entities added before public launch:** plans, subscriptions, credit_transactions, usage_records, payments, organizations, team_members, api_keys.

## 17. Key Relationships

```
User └── Projects
      ├── Script
      ├── Sources
      ├── Scenes
      │    └── Assets
      ├── AI Generations
      ├── Video Renders
      └── Preflight Reports
```

## 18. Project State Machine

`draft → researching → script_generating → storyboarding → generating_assets → generating_voice → generating_captions → rendering → quality_check → completed` · plus `failed`, `cancelled`.

## 19. Scene JSON Contract

The scene JSON is a critical internal contract between AI planning and rendering.

```json
{
  "id": "scene_01",
  "duration": 7,
  "narration": "...",
  "visual_type": "image",
  "visual_prompt": "...",
  "asset_id": "...",
  "caption": "...",
  "animation": "ken_burns",
  "transition": "fade",
  "background_music_level": 0.15
}
```

## 20. AI Generation Pipeline

1. Validate user input
2. Research topic (if enabled)
3. Collect and normalize sources
4. Determine unique story angle
5. Generate/edit script
6. Fact-check claims
7. Generate storyboard
8. Decide visual representation per scene
9. Generate prompts
10. Generate assets
11. Generate narration
12. Generate timed captions
13. Generate/select music
14. Build render manifest
15. Render
16. Run quality checks
17. Run policy preflight
18. Finalize project

## 21. Research Engine

- Accept a topic, question, or supplied research.
- Collect authoritative sources where possible.
- Store source URL/title/date and extracted claims.
- Separate source facts from generated interpretation.
- Provide sources to the user for review.
- Avoid copying source text into narration.
- For sensitive/current topics, require stronger source validation.

## 22. Script Engine

**Inputs:** topic, niche, audience, duration, tone, creator instructions, research sources, optional user script.

**Outputs:** title options, hook, story angle, sections, narration, estimated duration, claims/sources, creative notes.

## 23. Visual Director

The AI should choose the most useful visual representation rather than automatically generating one image for every sentence: Image, Generated video, Animated diagram, Chart, Timeline, Map, Quote card, Text animation, Screen recording/user upload, Split screen.

## 24. Template System

Templates are configuration + design language, not fixed scripts.

```
Template ├── typography ├── colors ├── caption rules ├── animation rules
         ├── transition rules ├── audio rules ├── scene presets └── thumbnail style
```

**Initial templates:** Dark Documentary, Modern Tech, Historical Documentary, Cartoon Explainer, Minimal Educational.

## 25. Video Engine

Build reusable video primitives: Scene, ImageScene, VideoScene, TextScene, ChartScene, MapScene, TimelineScene, QuoteScene, SplitScreenScene. Fade/Slide/Zoom/Cut transitions. Ken Burns/Pan/Scale/Text Reveal animations.

Remotion is the proposed rendering foundation because it supports React-based programmatic video creation, parameterization, server-side rendering and batch rendering. Its commercial/automation licensing must be reviewed before public launch and budgeted accordingly.

## 26. Voice and Caption Pipeline

```
Narration text → TTS provider → Audio file + timing/alignment
  → Caption generator → Caption JSON → Remotion composition
```

ElevenLabs provides a text-to-speech API and a timing endpoint that returns character alignment data, useful for synchronized captions.

## 27. Asset Management

Each asset should store: asset type, storage key/url, provider, prompt, model, dimensions, duration, cost, source type, license/provenance, AI-generated flag, realistic flag, disclosure requirement, project/scene relationship.

## 28. Rendering Strategy

Never keep an HTTP request open while a video is being generated.

```
POST /projects/:id/generate
  ↓ Create generation record
  ↓ Enqueue Sidekiq job
  ↓ Return job/project status
  ↓ Frontend receives progress
  ↓ Jobs execute independently
  ↓ Render worker produces MP4
  ↓ Upload to object storage
  ↓ Mark render completed
```

Every stage must be independently retryable. A failed scene should not force regeneration of the entire project.

## 29. API Surface — Initial

```
POST   /api/v1/projects
GET    /api/v1/projects
GET    /api/v1/projects/:id
PATCH  /api/v1/projects/:id
DELETE /api/v1/projects/:id
POST   /api/v1/projects/:id/script/generate
POST   /api/v1/projects/:id/storyboard/generate
GET    /api/v1/projects/:id/scenes
PATCH  /api/v1/scenes/:id
POST   /api/v1/scenes/:id/regenerate
POST   /api/v1/scenes/:id/assets/regenerate
POST   /api/v1/projects/:id/render
GET    /api/v1/projects/:id/renders
GET    /api/v1/templates
GET    /api/v1/assets
GET    /api/v1/projects/:id/preflight
```

## 30. Frontend State / Job Progress

Show a stage-based progress UI:

```
✓ Research  ✓ Script  ✓ Storyboard  ✓ Visuals  ● Voice
○ Captions  ○ Rendering  ○ Quality check  ○ YouTube preflight
```

## 31. Quality Assurance

A video is not considered successful merely because an MP4 exists. Check: script coherence, no obvious generation artifacts, narration quality, visual-to-narration relevance, caption synchronization, audio levels, correct resolution/aspect ratio, no broken/missing assets, no accidental duplicate scenes, policy preflight passed or warnings explicitly acknowledged.

## 32. YouTube Preflight Report

```
YOUTUBE CONTENT PREFLIGHT
Originality                  PASS / WARN
Narrative value              PASS / WARN
Repetition risk              PASS / WARN
Asset provenance             PASS / WARN
Reuse risk                   PASS / WARN
AI disclosure                REQUIRED / NOT REQUIRED / REVIEW
Copyright/license metadata   PASS / WARN
Advertiser suitability       REVIEW
Final status                 READY / REVIEW REQUIRED
```

This report must never claim guaranteed YPP approval.

## 33. Similarity / Repetition Detection

Compare a new project against the creator's recent projects using: script similarity, story structure similarity, scene order, visual prompt similarity, asset reuse, caption patterns, intro/outro patterns, template usage frequency.

If similarity becomes high, warn the creator and recommend changing the story angle, structure, visual mix, hook, or template.

## 34. Credits and Billing

Do not hard-code "one video = X credits". Measure actual provider and infrastructure costs.

```
credit_transactions: user_id, amount, type, reason, provider, generation_id, metadata, created_at
```

Example accounting: `+1000 subscription credits`, `-40 image generation`, `-30 voice generation`, `-50 render/processing`, `+500 purchased credits`.

## 35. Pricing Strategy

Pricing should be decided only after collecting real generation-cost data. Target pricing should cover: AI provider costs, rendering/infrastructure, storage/bandwidth, payment fees, support, failed-generation allowance, gross margin.

Possible future structure: Free/Trial → Creator → Pro → Agency/Team. Exact prices should follow measured unit economics.

## 36. Security

- Never expose AI provider API keys in the frontend.
- Use managed secrets/environment variables.
- Authorize every project/scene/asset access by user/organization.
- Use signed object-storage URLs.
- Validate uploads and media types.
- Rate-limit expensive generation endpoints.
- Use idempotency for payment and generation operations.
- Log security-sensitive events.
- Keep billing data separated from ordinary project data.

## 37. Observability

Record: provider request ID, generation/job ID, latency, input/output size, provider cost/usage, failure reason, retry count, project/scene ID, render duration.

## 38. Analytics

Track product events: signup, create_project, generate_script, generate_storyboard, generate_assets, regenerate_scene, render_video, download_video, purchase_credits, subscribe, cancel_subscription.

## 39. Internal Validation Plan

Before public launch, create at least 30 real videos with the application. Measure API cost/video, generation time, render time. Count manual fixes/video. Track failed generations. Score visual/narrative quality. Test multiple niches. Publish selected videos and monitor viewer response. Identify which templates produce the best outcomes.

## 40. Development Roadmap

- **Phase 0 — Product definition:** Requirements, target user, V1 scope, policy principles.
- **Phase 1 — Brand + UX:** Name, visual identity, Figma, design system, key screens.
- **Phase 2 — Foundation:** Next.js, Rails API, PostgreSQL, Redis, Sidekiq, storage, auth.
- **Phase 3 — AI pipeline:** Research, script, scene planner, visual director, provider adapters.
- **Phase 4 — Media pipeline:** Image, voice, captions, asset storage.
- **Phase 5 — Video engine:** Remotion/FFmpeg, templates, transitions, rendering.
- **Phase 6 — Editor:** Storyboard, preview, scene editing, regeneration.
- **Phase 7 — Policy/quality:** Preflight, provenance, repetition detection, disclosure logic.
- **Phase 8 — Internal validation:** 30+ videos, cost/quality analysis, improvements.
- **Phase 9 — SaaS:** Credits, subscriptions, payments, billing, usage.
- **Phase 10 — Beta:** 10 users → 50 → 100, feedback and reliability.
- **Phase 11 — Public launch:** Marketing, analytics, support, growth.

## 41. First 30 Days

- **Week 1:** Product specification, Figma foundations, Design system, Repository setup, Rails/Next.js foundation, Database/auth.
- **Week 2:** Projects, Script editor, AI script generation, Scene planner, Storyboard UI.
- **Week 3:** Image provider, Voice provider, Captions, Asset storage, Remotion prototype.
- **Week 4:** Complete render pipeline, First template, Regenerate scene, Quality checks, First real videos.

## 42. Month 2

5 templates, better editor, asset library, music/SFX, thumbnail generation, YouTube metadata, policy preflight, cost instrumentation.

## 43. Month 3

Research/source system, brand kit, credits, billing, landing page, analytics, private beta.

## 44. What NOT to Build in V1

Mobile application. Full Premiere/CapCut replacement. Dozens of AI providers. 50+ templates. Enterprise collaboration. Public API. Automated social publishing everywhere. Complex affiliate system.

## 45. Recommended Repository Structure

```
clipify/
├── apps/
│   ├── web/                 # Next.js
│   ├── api/                 # Rails API
│   └── renderer/            # Remotion renderer
├── packages/
│   ├── ui/
│   ├── types/
│   ├── video-schema/
│   └── prompts/
├── docs/
│   ├── product.md
│   ├── architecture.md
│   ├── api.md
│   ├── ai-pipeline.md
│   ├── video-engine.md
│   ├── policy.md
│   └── runbook.md
└── README.md
```

## 46. Definition of Done for V1

A user can create a project · paste a script · choose a template. The system creates a storyboard · generates assets · creates narration. Captions are synchronized. The renderer produces a valid MP4. A user can regenerate an individual scene. Asset provenance is stored. A YouTube-oriented preflight report is generated. Generation failures can be retried. The system records generation cost and duration. At least 30 internal videos have been produced and evaluated.

## 47. Long-Term Product Expansion

Idea-to-video autonomous workflow. Long-form documentaries. Shorts extraction from long-form videos. Automatic thumbnail/title/description generation. Brand kits. Voice/character consistency. Team collaboration. Agency workspaces. API access. Content calendar. Multi-platform export. Analytics-driven content suggestions.

## 48. Key External References

- YouTube Channel Monetization Policies — current guidance on original/authentic, inauthentic and reused content.
- YouTube — Disclosing use of GenAI content — current AI disclosure requirements.
- Remotion — programmatic React video creation and rendering.
- Google Gemini API — Nano Banana image generation models.
- ElevenLabs — text-to-speech and timestamp/alignment APIs.

## 49. Final Product Strategy

The product should be built as a real SaaS from the beginning, but validated first as an internal creator tool. The first customer is ourselves. We will use the application to produce real YouTube videos, measure quality and cost, improve the generation pipeline, and only then expose the system to paying users.

The most important differentiation is not simply AI generation. It is the combination of original storytelling, research, creator control, scene-level regeneration, visual diversity, reusable design systems, reliable rendering, asset provenance, cost-aware generation, and policy-aware preflight.

**North Star:** Build a creator studio that makes better videos faster — not a machine for mass-producing interchangeable videos.
