# Frontend (`apps/web`)

Next.js 16 (App Router, Turbopack) + React 19 + TypeScript. Runs on **:3001**
(Rails is on :3000).

## Stack

| Concern | Choice |
| --- | --- |
| Styling | Tailwind CSS v4, design tokens in `@clipify/ui/styles.css` |
| Components | `@clipify/ui` — `cn`, Button, Input/Textarea, Label, Card, Badge (shadcn-style primitives we own) |
| Server state | TanStack Query v5 |
| Types | `@clipify/types` (mirrors Rails serializers) + `@clipify/video-schema` (Scene contract) |
| Auth | JWT in an **httpOnly cookie**, never exposed to JS |

## Auth flow

```
Browser ──POST /api/auth/sign-in──▶ Next route handler ──▶ Rails /api/v1/auth/sign_in
                                          │ reads Authorization header from Rails
                                          ▼
                              Set-Cookie: clipify_token (httpOnly)
```

- `src/app/api/auth/{sign-in,sign-up,sign-out,session}/route.ts` — auth proxies.
- `src/app/api/v1/[...path]/route.ts` — transparent authenticated proxy: the
  client calls `/api/v1/...` same-origin, this handler forwards to Rails with the
  cookie's JWT as `Authorization: Bearer`.
- `src/lib/server/rails.ts` — `railsFetch()` / `currentUser()` for server code.
- `src/proxy.ts` (Next 16's renamed `middleware`) — redirects unauthenticated
  users away from `/dashboard` and `/projects/*`. The real check is still the
  Rails token verification in the proxy route.

## Data layer

- `src/lib/api/client.ts` — `apiFetch<T>()` against the `/api/v1` proxy, throws
  `ApiClientError` with status + payload.
- `src/lib/api/projects.ts`, `templates.ts` — query-key factories + hooks
  (`useProjects`, `useProject`, `useProjectScenes`, `useCreateProject`, …).
- `src/lib/api/auth.ts` — `useSession`, `useSignIn`, `useSignUp`, `useSignOut`.
- `src/app/providers.tsx` — `QueryClientProvider`; sub-500 errors don't retry.

## Routes

| Path | Notes |
| --- | --- |
| `/` | Landing page |
| `/login`, `/signup` | `(auth)` group |
| `/dashboard` | `(app)` group — project list; layout redirects if not signed in |
| `/projects/new` | Create form (title, topic/script, format, duration, template) |
| `/projects/[id]` | Project detail — status, `PipelineProgress` (spec §30), storyboard list |

## Not built yet

Storyboard/scene editing, asset library, render screen, billing, brand kit,
real Modal primitive, landing-page showcase sections. Generation buttons are
disabled pending the Phase 3 pipeline.

## Commands

```bash
pnpm --filter @clipify/web dev        # http://localhost:3001
pnpm --filter @clipify/web build
pnpm turbo run typecheck lint test    # whole JS workspace
```
