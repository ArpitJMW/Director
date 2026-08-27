# Object Storage

Generated and uploaded media live in object storage (spec §12); the `assets`
table is the source of truth for keys, size, checksum, dimensions and provenance
(spec §27). URLs handed to the browser are always time-limited (spec §36).

## Backends

`Storage.service` returns the configured adapter. `STORAGE_BACKEND` = `disk` |
`s3`; defaults to `disk` unless `S3_BUCKET` is set.

| Adapter | Use | URL scheme |
| --- | --- | --- |
| `Storage::DiskAdapter` | dev / test | signed app endpoint `GET /api/v1/files?key=&token=&expires=` (HMAC of key+expiry with `secret_key_base`) |
| `Storage::S3Adapter` | staging / prod — AWS S3 or Cloudflare R2 (`S3_ENDPOINT` + path-style) | S3/R2 **presigned GET** URL |

Interface (`Storage::Service`): `upload(key:, io:, content_type:)`,
`url(key:, expires_in:)`, `download(key:)`, `delete(key:)`, `exists?(key:)`.

## Creating assets

```ruby
Asset.store!(
  project:, asset_type: "image", io:, content_type: "image/png",
  scene: nil, source_type: "ai_generated", provider: "gemini", prompt: "...",
  ai_generation: gen, requires_disclosure: false
)
```

- Runs in a transaction — the row is rolled back if the upload fails (no orphans).
- Key: `projects/<project_id>/<public_id>.<ext>` or
  `projects/<project_id>/scenes/<scene_id>/<public_id>.<ext>`.
- Reads image dimensions with FastImage (no ImageMagick/vips).
- `source_type: "ai_generated"` implies `ai_generated: true`.

`asset.signed_url(expires_in: 3600)` → a fetchable URL for whichever backend.
`AssetSerializer` exposes it as `url`.

## API

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/api/v1/projects/:id/assets` | multipart `file` (+ `asset_type`, `scene_id?`) — user-provided upload, ≤ 50 MB, allowlisted MIME types |
| GET | `/api/v1/assets?project_id=&type=` | list (scoped to your projects) |
| GET | `/api/v1/files?key=&token=&expires=` | disk backend only; the HMAC token is the capability, no session needed |

## Disk files on disk

`apps/api/storage/uploads/…` (gitignored). Tests use `tmp/test_storage`, wiped
after the suite.
