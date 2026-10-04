"use client";

import { useState } from "react";
import { Badge, Button, Card, Select, Skeleton, Textarea, cn } from "@clipify/ui";
import type { SceneResource, UpdateShotInput } from "@clipify/types";
import {
  CAMERA_INTENSITIES,
  CAMERA_MOTIONS,
  OVERLAY_TYPES,
  TEXT_STYLES,
  type Overlay,
} from "@clipify/video-schema";
import { useRegenerateSceneAsset, useUpdateScene } from "@/lib/api/pipeline";

// --- Small readers for the loosely-typed camera/motion jsonb -----------------

function cameraMotion(camera: unknown): string {
  return camera && typeof camera === "object" && typeof (camera as Record<string, unknown>).movement === "string"
    ? ((camera as Record<string, unknown>).movement as string)
    : "";
}

function intensity(motion: unknown): string {
  return motion && typeof motion === "object" && typeof (motion as Record<string, unknown>).intensity === "string"
    ? ((motion as Record<string, unknown>).intensity as string)
    : "";
}

const TEXT_STYLE_LABELS: Record<string, string> = {
  stagger_reveal: "Stagger reveal",
  punch_in: "Punch in",
  big_number: "Big number",
  quote: "Quote",
  list_reveal: "List reveal",
  timeline: "Timeline",
};

function labelize(value: string) {
  return value.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}

// --- Method badge + Why line + text preview (always visible, no edit UI) ----

/** Task 6 Part E: one badge for the unit's QA state, with its evidence line. */
function QaBadge({ qa }: { qa: NonNullable<SceneResource["qa"]> }) {
  const top = qa.issues.find((i) => i.severity !== "info") ?? qa.issues[0];
  const label =
    qa.repaired
      ? `QA repaired${top ? ` · ${top.issue_type.replace(/_/g, " ")}` : ""}`
      : qa.status === "passed"
        ? "QA passed"
        : qa.status === "unavailable"
          ? "QA unavailable"
          : `QA: ${top ? top.issue_type.replace(/_/g, " ") : "issue"}`;
  const tone = qa.status === "failed" && !qa.repaired ? "danger" : qa.repaired ? "success" : qa.status === "passed" ? "success" : "warning";
  return (
    <span title={top?.evidence} className="inline-flex flex-col">
      <Badge tone={tone}>{label}</Badge>
      {top && !qa.repaired && (
        <span className="mt-0.5 max-w-xs text-[11px] italic text-muted">{top.evidence}</span>
      )}
    </span>
  );
}

function MethodBadge({ scene }: { scene: SceneResource["scene"] }) {
  const isText = scene.asset_strategy === "text";
  const style = scene.text_spec?.text_style;
  return (
    <Badge tone={isText ? "info" : "neutral"}>
      {isText ? `Text${style ? ` · ${TEXT_STYLE_LABELS[style] ?? style}` : ""}` : "Image"}
    </Badge>
  );
}

function TextPreview({ spec }: { spec: SceneResource["scene"]["text_spec"] }) {
  if (!spec) return <p className="text-xs text-muted">Text card — not planned yet.</p>;

  if (spec.text_style === "list_reveal" || spec.text_style === "timeline") {
    const items = spec.items ?? [];
    return items.length > 0 ? (
      <ul className="flex flex-wrap gap-1">
        {items.map((item, i) => (
          <li key={i} className="rounded bg-surface-2 px-1.5 py-0.5 text-[11px] text-muted">
            {item}
          </li>
        ))}
      </ul>
    ) : (
      <p className="text-xs text-muted">No items yet.</p>
    );
  }

  if (spec.text_style === "big_number") {
    return (
      <p className="text-xs text-muted">
        <span className="font-semibold text-foreground">{spec.number ?? "—"}</span>
        {spec.unit ? ` ${spec.unit}` : ""}
        {spec.lines?.length ? ` — ${spec.lines.join(" ")}` : ""}
      </p>
    );
  }

  return <p className="line-clamp-3 text-xs italic text-muted">{spec.lines?.join(" ") || "—"}</p>;
}

// --- The "Direct" panel: every override, collapsed by default ---------------

type DirectionDraft = {
  camera_motion: string;
  camera_intensity: string;
  transition_in: string;
  overlay_type: string;
  overlay_text: string;
  overlay_value: string;
  text_style: string;
  items: string;
  number: string;
  unit: string;
};

function draftFromScene(scene: SceneResource["scene"]): DirectionDraft {
  const overlay = scene.overlay as Overlay | null | undefined;
  return {
    camera_motion: cameraMotion(scene.camera),
    camera_intensity: intensity(scene.motion),
    transition_in: scene.transition ?? "cut",
    overlay_type: overlay?.type ?? "none",
    overlay_text: overlay?.text ?? "",
    overlay_value: overlay?.value ?? "",
    text_style: scene.text_spec?.text_style ?? "stagger_reveal",
    items: (scene.text_spec?.items ?? []).join(", "),
    number: scene.text_spec?.number != null ? String(scene.text_spec.number) : "",
    unit: scene.text_spec?.unit ?? "",
  };
}

type ShotDraft = { id: string; camera_motion: string; camera_intensity: string; overlay_type: string; overlay_text: string };

function shotDrafts(shots: SceneResource["scene"]["shots"]): ShotDraft[] {
  // Task 4.1 real-run bug fix: `shots` is only present on the JSON contract
  // when the scene actually has any (Scene#to_scene_json, Phase 1 Task 2 —
  // absent, not `[]`, so old consumers/manifests are unaffected) — a text
  // scene or a short unsplit image scene sends no `shots` key at all. The
  // TS type says `Shot[]` but that's a compile-time-only promise; reading
  // `.length`/`.map` on the real `undefined` crashed the whole storyboard
  // page (found via Task 4.1's first real Playwright run — no unit/request
  // spec exercises this component's rendering, only the Rails JSON shape).
  return (shots ?? []).map((shot) => {
    const overlay = shot.overlay as Overlay | null | undefined;
    return {
      id: shot.id,
      camera_motion: shot.camera_movement ?? "",
      camera_intensity: intensity(shot.motion),
      overlay_type: overlay?.type ?? "none",
      overlay_text: overlay?.text ?? "",
    };
  });
}

function DirectPanel({
  scene,
  projectId,
  onDone,
}: {
  scene: SceneResource;
  projectId: string;
  onDone: () => void;
}) {
  const update = useUpdateScene(projectId);
  const [method, setMethod] = useState<"image" | "text">(scene.scene.asset_strategy === "text" ? "text" : "image");
  const [draft, setDraft] = useState<DirectionDraft>(draftFromScene(scene.scene));
  const [shots, setShots] = useState<ShotDraft[]>(shotDrafts(scene.scene.shots));
  const set = <K extends keyof DirectionDraft>(key: K, value: DirectionDraft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  const isText = method === "text";

  function save() {
    const shotsPayload: UpdateShotInput[] = shots.map((s) => ({
      id: s.id,
      direction: {
        camera_motion: (s.camera_motion || undefined) as never,
        camera_intensity: (s.camera_intensity || undefined) as never,
        overlay:
          s.overlay_type === "none" || !s.overlay_type
            ? { type: "none" }
            : { type: s.overlay_type as never, text: s.overlay_text || undefined },
      },
    }));

    update.mutate({
      sceneId: scene.id,
      input: {
        asset_strategy: method,
        direction: {
          camera_motion: (draft.camera_motion || undefined) as never,
          camera_intensity: (draft.camera_intensity || undefined) as never,
          transition_in: (draft.transition_in || undefined) as never,
          overlay:
            draft.overlay_type === "none" || !draft.overlay_type
              ? { type: "none" }
              : { type: draft.overlay_type as never, text: draft.overlay_text || undefined, value: draft.overlay_value || undefined },
          ...(isText
            ? {
                text_style: (draft.text_style || undefined) as never,
                items: draft.items
                  .split(",")
                  .map((s) => s.trim())
                  .filter(Boolean),
                number: draft.number.trim() === "" ? undefined : draft.number.trim(),
                unit: draft.unit || undefined,
              }
            : {}),
        },
        shots: method === "image" ? shotsPayload : undefined,
      },
    });
  }

  return (
    <div className="flex flex-col gap-3 border-t border-border bg-surface-2/40 p-3">
      <div className="flex items-center gap-2">
        <span className="text-[11px] font-medium text-muted">Method</span>
        <div className="flex overflow-hidden rounded-md border border-border text-xs">
          {(["image", "text"] as const).map((m) => (
            <button
              key={m}
              type="button"
              className={cn(
                "px-2.5 py-1 capitalize",
                method === m ? "bg-accent text-white" : "bg-surface-1 text-muted hover:text-foreground",
              )}
              onClick={() => setMethod(m)}
            >
              {m}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Field label="Camera motion">
          <Select value={draft.camera_motion} onChange={(e) => set("camera_motion", e.target.value)}>
            <option value="">Cycle (default)</option>
            {CAMERA_MOTIONS.map((m) => (
              <option key={m} value={m}>
                {labelize(m)}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Intensity">
          <Select value={draft.camera_intensity} onChange={(e) => set("camera_intensity", e.target.value)}>
            <option value="">Default</option>
            {CAMERA_INTENSITIES.map((i) => (
              <option key={i} value={i}>
                {labelize(i)}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Transition in">
          <Select value={draft.transition_in} onChange={(e) => set("transition_in", e.target.value)}>
            {["cut", "crossfade", "fade_from_black", "slide", "wipe", "zoom"].map((t) => (
              <option key={t} value={t}>
                {labelize(t)}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Overlay">
          <Select value={draft.overlay_type} onChange={(e) => set("overlay_type", e.target.value)}>
            {OVERLAY_TYPES.map((t) => (
              <option key={t} value={t}>
                {t === "none" ? "None" : labelize(t)}
              </option>
            ))}
          </Select>
        </Field>
        {draft.overlay_type !== "none" && (
          <Field label="Overlay text" className="col-span-2">
            <input
              className="h-9 w-full rounded-md border border-border bg-surface-1 px-2 text-xs"
              value={draft.overlay_text}
              onChange={(e) => set("overlay_text", e.target.value)}
              placeholder="e.g. Johannes Gutenberg"
            />
          </Field>
        )}
        {draft.overlay_type === "stat_callout" && (
          <Field label="Overlay value" className="col-span-2">
            <input
              className="h-9 w-full rounded-md border border-border bg-surface-1 px-2 text-xs"
              value={draft.overlay_value}
              onChange={(e) => set("overlay_value", e.target.value)}
              placeholder="e.g. 42%"
            />
          </Field>
        )}
      </div>

      {isText && (
        <div className="grid grid-cols-2 gap-2 border-t border-border pt-2">
          <Field label="Text style">
            <Select value={draft.text_style} onChange={(e) => set("text_style", e.target.value)}>
              {TEXT_STYLES.map((s) => (
                <option key={s} value={s}>
                  {TEXT_STYLE_LABELS[s] ?? labelize(s)}
                </option>
              ))}
            </Select>
          </Field>
          {(draft.text_style === "list_reveal" || draft.text_style === "timeline") && (
            <Field label="Items (comma-separated)" className="col-span-2">
              <input
                className="h-9 w-full rounded-md border border-border bg-surface-1 px-2 text-xs"
                value={draft.items}
                onChange={(e) => set("items", e.target.value)}
                placeholder="Venice, Paris, Mainz"
              />
            </Field>
          )}
          {draft.text_style === "big_number" && (
            <>
              <Field label="Number">
                <input
                  className="h-9 w-full rounded-md border border-border bg-surface-1 px-2 text-xs"
                  value={draft.number}
                  onChange={(e) => set("number", e.target.value)}
                  placeholder="90"
                />
              </Field>
              <Field label="Unit">
                <input
                  className="h-9 w-full rounded-md border border-border bg-surface-1 px-2 text-xs"
                  value={draft.unit}
                  onChange={(e) => set("unit", e.target.value)}
                  placeholder="%"
                />
              </Field>
            </>
          )}
        </div>
      )}

      {!isText && shots.length > 0 && (
        <div className="flex flex-col gap-2 border-t border-border pt-2">
          <span className="text-[11px] font-medium text-muted">Shots</span>
          {shots.map((shot, i) => (
            <div key={shot.id} className="grid grid-cols-3 items-center gap-2 text-xs">
              <span className="text-muted">Shot {i + 1}</span>
              <Select
                value={shot.camera_motion}
                onChange={(e) =>
                  setShots((prev) => prev.map((s, j) => (j === i ? { ...s, camera_motion: e.target.value } : s)))
                }
                className="h-8 text-xs"
              >
                <option value="">Cycle (default)</option>
                {CAMERA_MOTIONS.map((m) => (
                  <option key={m} value={m}>
                    {labelize(m)}
                  </option>
                ))}
              </Select>
              <Select
                value={shot.camera_intensity}
                onChange={(e) =>
                  setShots((prev) => prev.map((s, j) => (j === i ? { ...s, camera_intensity: e.target.value } : s)))
                }
                className="h-8 text-xs"
              >
                <option value="">Default</option>
                {CAMERA_INTENSITIES.map((int) => (
                  <option key={int} value={int}>
                    {labelize(int)}
                  </option>
                ))}
              </Select>
            </div>
          ))}
        </div>
      )}

      {update.isError && (
        <p className="text-xs text-danger">
          {update.error instanceof Error ? update.error.message : "Could not save — check the values above."}
        </p>
      )}

      <div className="flex justify-end gap-2 border-t border-border pt-2">
        <Button size="sm" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
        <Button size="sm" disabled={update.isPending} onClick={() => save()}>
          {update.isPending ? "Saving…" : "Save direction"}
        </Button>
      </div>
    </div>
  );
}

function Field({ label, className, children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <label className={cn("flex flex-col gap-1", className)}>
      <span className="text-[11px] font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}

// --- The card itself ---------------------------------------------------------

export function SceneCard({
  scene,
  projectId,
  editable,
}: {
  scene: SceneResource;
  projectId: string;
  editable: boolean;
}) {
  const regenerate = useRegenerateSceneAsset(projectId);
  const update = useUpdateScene(projectId);
  const [editing, setEditing] = useState(false);
  const [directing, setDirecting] = useState(false);
  const [narration, setNarration] = useState(scene.scene.narration ?? "");
  const [prompt, setPrompt] = useState(scene.scene.visual_prompt ?? "");

  const generating = scene.status === "generating_asset" || scene.status === "generating_prompt";
  const hasImage = Boolean(scene.selected_asset?.url);
  const isText = scene.scene.asset_strategy === "text";
  const shotCount = (scene.scene.shots ?? []).length; // see shotDrafts() above — `shots` is absent, not [], when there are none
  const reason = scene.scene.direction_reason ?? scene.scene.visual_reason;

  return (
    <Card className="flex flex-col overflow-hidden">
      <div className="relative aspect-video bg-surface-2">
        {isText ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 bg-surface-2 p-4">
            <TextPreview spec={scene.scene.text_spec} />
          </div>
        ) : generating && !hasImage ? (
          <Skeleton className="absolute inset-0 rounded-none" />
        ) : hasImage ? (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img
            src={scene.selected_asset!.url!}
            alt={scene.scene.caption ?? scene.scene.id}
            className={cn(
              "h-full w-full object-cover transition-opacity duration-300",
              regenerate.isPending && "opacity-40",
            )}
          />
        ) : (
          <div className="flex h-full items-center justify-center text-xs text-muted">
            {scene.scene.visual_type.replace(/_/g, " ")}
          </div>
        )}
        <span className="absolute left-2 top-2 rounded bg-black/60 px-1.5 py-0.5 text-[10px] font-medium text-white">
          {scene.scene.id}
        </span>
        <span className="absolute right-2 top-2 rounded bg-black/60 px-1.5 py-0.5 text-[10px] text-white">
          {scene.scene.duration}s
        </span>
      </div>

      <div className="flex flex-1 flex-col gap-2 p-3">
        <div className="flex flex-wrap items-center gap-1.5">
          <MethodBadge scene={scene.scene} />
          {shotCount > 0 && <Badge>{shotCount} shots</Badge>}
          {scene.qa && <QaBadge qa={scene.qa} />}
          {scene.needs_regeneration && <Badge tone="warning">Needs regeneration</Badge>}
          {!scene.needs_regeneration && scene.needs_rerender && <Badge tone="info">Needs re-render</Badge>}
        </div>
        {reason && <p className="text-[11px] italic text-muted">Why: {reason}</p>}

        {editing ? (
          <>
            <label className="text-[11px] font-medium text-muted">Narration</label>
            <Textarea
              rows={3}
              value={narration}
              onChange={(e) => setNarration(e.target.value)}
              className="text-xs"
            />
            <label className="text-[11px] font-medium text-muted">Visual prompt</label>
            <Textarea
              rows={2}
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              className="text-xs"
            />
            <div className="flex gap-2">
              <Button
                size="sm"
                disabled={update.isPending}
                onClick={() =>
                  update.mutate(
                    { sceneId: scene.id, input: { narration, visual_prompt: prompt } },
                    { onSuccess: () => setEditing(false) },
                  )
                }
              >
                Save
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setEditing(false)}>
                Cancel
              </Button>
            </div>
          </>
        ) : (
          <>
            <p className="line-clamp-4 text-xs text-muted">{scene.scene.narration}</p>
            {scene.narration_audio?.url && (
              <audio controls src={scene.narration_audio.url} className="h-7 w-full" />
            )}
            {editable && (
              <div className="mt-auto flex flex-wrap gap-3 pt-1 text-xs">
                <button
                  type="button"
                  className="text-accent disabled:opacity-50"
                  disabled={regenerate.isPending}
                  onClick={() => regenerate.mutate(scene.id)}
                >
                  {regenerate.isPending ? "Regenerating…" : "Regenerate image"}
                </button>
                <button type="button" className="text-accent" onClick={() => setEditing(true)}>
                  Edit scene
                </button>
                <button type="button" className="text-accent" onClick={() => setDirecting((d) => !d)}>
                  {directing ? "Close direct panel" : "Direct ▾"}
                </button>
              </div>
            )}
          </>
        )}
      </div>

      {editable && directing && (
        <DirectPanel scene={scene} projectId={projectId} onDone={() => setDirecting(false)} />
      )}
    </Card>
  );
}
