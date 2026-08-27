"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useRef } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@clipify/ui";
import { useProject, useProjectScenes, projectKeys } from "@/lib/api/projects";
import {
  useGenerateAssets,
  useGenerateScript,
  useGenerateStoryboard,
  useGenerateVoice,
  useProjectJobs,
  useRegenerateSceneAsset,
} from "@/lib/api/pipeline";
import { ProjectStatusBadge } from "@/components/project-status-badge";
import { PipelineProgress } from "@/components/pipeline-progress";

export default function ProjectPage() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();
  const { data: project, isLoading, isError, error } = useProject(id);
  const { data: scenes } = useProjectScenes(id);
  const { data: jobs } = useProjectJobs(id);
  const generateScript = useGenerateScript(id);
  const generateStoryboard = useGenerateStoryboard(id);
  const generateAssets = useGenerateAssets(id);
  const generateVoice = useGenerateVoice(id);
  const regenerateSceneAsset = useRegenerateSceneAsset(id);

  const scriptJob = jobs?.find((j) => j.stage === "script");
  const storyboardJob = jobs?.find((j) => j.stage === "storyboard");
  const assetsJob = jobs?.find((j) => j.stage === "assets" && !j.scene_id);
  const voiceJob = jobs?.find((j) => j.stage === "voice");
  const scriptRunning = Boolean(scriptJob?.active);
  const storyboardRunning = Boolean(storyboardJob?.active);
  const assetsRunning = jobs?.some((j) => j.stage === "assets" && j.active) ?? false;
  const voiceRunning = Boolean(voiceJob?.active);
  const anyRunning = scriptRunning || storyboardRunning || assetsRunning || voiceRunning;

  // When a job finishes, refresh the project + scenes.
  const wasRunning = useRef(false);
  useEffect(() => {
    if (wasRunning.current && !anyRunning) {
      qc.invalidateQueries({ queryKey: projectKeys.detail(id) });
      qc.invalidateQueries({ queryKey: projectKeys.scenes(id) });
    }
    wasRunning.current = anyRunning;
  }, [anyRunning, id, qc]);

  if (isLoading) return <p className="text-sm text-muted">Loading…</p>;
  if (isError) return <p className="text-sm text-danger">{(error as Error).message}</p>;
  if (!project) return null;

  const script = project.current_script;

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div className="flex items-start justify-between">
        <div>
          <Link href="/dashboard" className="text-sm text-muted hover:text-foreground">
            ← Projects
          </Link>
          <h1 className="mt-1 text-2xl font-semibold">{project.title}</h1>
          {project.topic && <p className="mt-1 max-w-2xl text-sm text-muted">{project.topic}</p>}
        </div>
        <ProjectStatusBadge status={project.status} />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Pipeline</CardTitle>
        </CardHeader>
        <CardContent>
          <PipelineProgress status={project.status} />
          <div className="mt-4 flex items-center gap-3">
            <Button
              size="sm"
              disabled={scriptRunning || generateScript.isPending}
              onClick={() => generateScript.mutate()}
            >
              {scriptRunning
                ? "Generating…"
                : script
                  ? "Regenerate script"
                  : "Generate script"}
            </Button>
            {scriptJob?.status === "failed" && (
              <span className="text-xs text-danger">
                Failed: {scriptJob.failure_reason ?? "unknown error"}
              </span>
            )}
            {generateScript.isError && (
              <span className="text-xs text-danger">
                {(generateScript.error as Error).message}
              </span>
            )}
          </div>
        </CardContent>
      </Card>

      {script && (
        <Card>
          <CardHeader>
            <CardTitle>Script</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-3 text-sm">
            <div>
              <span className="text-muted">Title</span>
              <p className="font-medium">{script.selected_title}</p>
            </div>
            {script.hook && (
              <div>
                <span className="text-muted">Hook</span>
                <p>{script.hook}</p>
              </div>
            )}
            {script.story_angle && (
              <div>
                <span className="text-muted">Angle</span>
                <p>{script.story_angle}</p>
              </div>
            )}
            <div>
              <span className="text-muted">
                Narration · ~{script.estimated_duration_seconds ?? "?"}s · v{script.version}
              </span>
              <p className="mt-1 whitespace-pre-wrap">{script.full_narration}</p>
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Storyboard</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="mb-4 flex flex-wrap items-center gap-3">
            <Button
              size="sm"
              disabled={!script || storyboardRunning || generateStoryboard.isPending}
              onClick={() => generateStoryboard.mutate()}
            >
              {storyboardRunning
                ? "Planning…"
                : scenes?.length
                  ? "Regenerate storyboard"
                  : "Generate storyboard"}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={!scenes?.length || assetsRunning || generateAssets.isPending}
              onClick={() => generateAssets.mutate()}
            >
              {assetsRunning ? "Generating images…" : "Generate images"}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={!scenes?.length || voiceRunning || generateVoice.isPending}
              onClick={() => generateVoice.mutate()}
            >
              {voiceRunning ? "Narrating…" : "Generate narration"}
            </Button>
            {!script && (
              <span className="text-xs text-muted">Generate a script first.</span>
            )}
            {storyboardJob?.status === "failed" && (
              <span className="text-xs text-danger">
                Failed: {storyboardJob.failure_reason ?? "unknown error"}
              </span>
            )}
            {assetsJob?.status === "failed" && (
              <span className="text-xs text-danger">
                Image generation failed: {assetsJob.failure_reason ?? "unknown error"}
              </span>
            )}
          </div>
          {!scenes?.length && !storyboardRunning && (
            <p className="text-sm text-muted">No scenes yet.</p>
          )}
          <ol className="flex flex-col gap-3">
            {scenes?.map((s) => (
              <li key={s.id} className="flex gap-3 rounded-md border border-border p-3">
                {s.selected_asset?.url ? (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img
                    src={s.selected_asset.url}
                    alt={s.scene.caption ?? s.scene.id}
                    className="h-20 w-32 shrink-0 rounded object-cover"
                  />
                ) : (
                  <div className="flex h-20 w-32 shrink-0 items-center justify-center rounded bg-surface-2 text-xs text-muted">
                    {s.status === "generating_asset" ? "…" : "no image"}
                  </div>
                )}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium">
                      {s.scene.id} · {s.scene.visual_type.replace(/_/g, " ")}
                    </span>
                    <span className="text-xs text-muted">{s.scene.duration}s</span>
                  </div>
                  {s.scene.narration && (
                    <p className="mt-1 line-clamp-2 text-sm text-muted">{s.scene.narration}</p>
                  )}
                  <div className="mt-1 flex items-center gap-3 text-xs">
                    {s.selected_asset && (
                      <button
                        type="button"
                        className="text-accent disabled:opacity-50"
                        disabled={assetsRunning}
                        onClick={() => regenerateSceneAsset.mutate(s.id)}
                      >
                        Regenerate image
                      </button>
                    )}
                    {s.narration_audio?.url && (
                      <audio
                        controls
                        src={s.narration_audio.url}
                        className="h-7 max-w-[220px]"
                      />
                    )}
                    {s.captions.length > 0 && (
                      <span className="text-muted">{s.captions.length} caption cues</span>
                    )}
                  </div>
                </div>
              </li>
            ))}
          </ol>
        </CardContent>
      </Card>
    </div>
  );
}
