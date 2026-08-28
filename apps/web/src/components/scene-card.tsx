"use client";

import { useState } from "react";
import { Button, Card, Skeleton, Textarea, cn } from "@clipify/ui";
import type { SceneResource } from "@clipify/types";
import { useRegenerateSceneAsset, useUpdateScene } from "@/lib/api/pipeline";

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
  const [narration, setNarration] = useState(scene.scene.narration ?? "");
  const [prompt, setPrompt] = useState(scene.scene.visual_prompt ?? "");

  const generating = scene.status === "generating_asset" || scene.status === "generating_prompt";
  const hasImage = Boolean(scene.selected_asset?.url);

  return (
    <Card className="flex flex-col overflow-hidden">
      <div className="relative aspect-video bg-surface-2">
        {generating && !hasImage ? (
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
              <div className="mt-auto flex gap-3 pt-1 text-xs">
                <button
                  type="button"
                  className="text-accent disabled:opacity-50"
                  disabled={regenerate.isPending}
                  onClick={() => regenerate.mutate(scene.id)}
                >
                  {regenerate.isPending ? "Regenerating…" : "Regenerate image"}
                </button>
                <button
                  type="button"
                  className="text-accent"
                  onClick={() => setEditing(true)}
                >
                  Edit scene
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </Card>
  );
}
