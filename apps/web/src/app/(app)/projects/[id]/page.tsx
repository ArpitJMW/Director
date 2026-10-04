"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { Button, Card, CardContent, CardHeader, CardTitle, Progress } from "@clipify/ui";
import { projectKeys, useProject, useProjectScenes, useUpdateProject } from "@/lib/api/projects";
import {
  useContinuePipeline,
  useProjectJobs,
  useRegenerateAllImages,
  useRenderVideo,
  useRestartPipeline,
  useRevisePipeline,
  useStartPipeline,
  useStopPipeline,
} from "@/lib/api/pipeline";
import { VISUAL_STYLES } from "@/lib/constants";
import { useProjectRenders } from "@/lib/api/renders";
import { ProjectStatusBadge } from "@/components/project-status-badge";
import { GenerationStepper } from "@/components/generation-stepper";
import { SceneCard } from "@/components/scene-card";
import { PreflightCard } from "@/components/preflight-card";

const STAGE_LABEL: Record<string, string> = {
  script: "Script",
  storyboard: "Storyboard",
  assets: "Visuals",
  voice: "Voice & captions",
  preflight: "Preflight",
  render: "Render",
};

export default function ProjectPage() {
  const { id } = useParams<{ id: string }>();

  const { data: jobs = [] } = useProjectJobs(id);
  const anyJobActive = jobs.some((j) => j.active);

  const { data: project, isLoading, isError, error } = useProject(id, {
    refetchInterval: anyJobActive ? 1500 : false,
  });
  const { data: scenes = [] } = useProjectScenes(id, { poll: anyJobActive });

  // Task 6.1: the project query only polls while a job is active, so a page
  // that saw the last job still "active" never fetched the checkpoint it
  // reached afterwards. Refresh once when the last job finishes.
  const queryClient = useQueryClient();
  const wasActive = useRef(anyJobActive);
  useEffect(() => {
    if (wasActive.current && !anyJobActive) {
      queryClient.invalidateQueries({ queryKey: projectKeys.detail(id) });
      queryClient.invalidateQueries({ queryKey: projectKeys.scenes(id) });
    }
    wasActive.current = anyJobActive;
  }, [anyJobActive, id, queryClient]);

  const start = useStartPipeline(id);
  const stop = useStopPipeline(id);
  const restart = useRestartPipeline(id);
  const cont = useContinuePipeline(id);
  const revise = useRevisePipeline(id);
  const render = useRenderVideo(id);
  const regenAll = useRegenerateAllImages(id);
  const updateProject = useUpdateProject(id);
  const { data: renders } = useProjectRenders(id);

  if (isLoading) return <p className="text-sm text-muted">Loading…</p>;
  if (isError) return <p className="text-sm text-danger">{(error as Error).message}</p>;
  if (!project) return null;

  const script = project.current_script;
  const checkpoint = project.pipeline.checkpoint;
  const isAuto = project.pipeline.mode === "auto";
  const started = isAuto || Boolean(script) || scenes.length > 0;
  const running = Boolean(project.pipeline.active_stage) || anyJobActive;
  const failedStage = jobs.find((j) => j.status === "failed" && !j.scene_id)?.stage;
  const latestRender = renders?.[0];

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div className="flex items-start justify-between">
        <div>
          <Link href="/dashboard" className="text-sm text-muted hover:text-foreground">
            ← Projects
          </Link>
          <h1 className="mt-1 text-2xl font-semibold">{project.title}</h1>
          {project.topic && (
            <p className="mt-1 max-w-2xl text-sm text-muted line-clamp-2">{project.topic}</p>
          )}
        </div>
        <div className="flex flex-col items-end gap-2">
          <ProjectStatusBadge status={project.status} checkpoint={checkpoint} />
          <div className="flex flex-wrap items-center justify-end gap-2">
            {running && (
              <Button
                size="sm"
                variant="outline"
                disabled={stop.isPending}
                onClick={() => stop.mutate()}
              >
                {stop.isPending ? "Stopping…" : "Stop"}
              </Button>
            )}
            {started && (
              <Button
                size="sm"
                variant="outline"
                disabled={restart.isPending}
                onClick={() => {
                  if (
                    window.confirm(
                      "Start over? This deletes the current script, storyboard, and video, then regenerates everything from your project settings.",
                    )
                  ) {
                    restart.mutate();
                  }
                }}
              >
                {restart.isPending ? "Restarting…" : "Start over"}
              </Button>
            )}
            <Link href="/projects/new">
              <Button size="sm">New video</Button>
            </Link>
          </div>
        </div>
      </div>

      {/* --- Not started: one button --- */}
      {!started && (
        <Card>
          <CardContent className="flex flex-col items-center gap-4 py-10 text-center">
            <p className="max-w-md text-sm text-muted">
              Clipify will write the script, plan the storyboard, generate the visuals, and
              pause for your review before narration and rendering.
            </p>
            <Button
              size="lg"
              disabled={start.isPending}
              onClick={() => start.mutate()}
            >
              {start.isPending ? "Starting…" : "Start generation"}
            </Button>
          </CardContent>
        </Card>
      )}

      {/* --- Progress stepper --- */}
      {started && (
        <Card>
          <CardContent className="pt-5">
            <GenerationStepper project={project} jobs={jobs} />
          </CardContent>
        </Card>
      )}

      {/* --- Failure banner --- */}
      {project.status === "failed" && (
        <Card className="border-danger/50">
          <CardContent className="flex flex-col gap-3 py-4">
            <p className="text-sm">
              The <span className="font-medium">{STAGE_LABEL[failedStage ?? ""] ?? "pipeline"}</span>{" "}
              stage failed
              {project.failure_reason ? `: ${project.failure_reason}` : "."}
            </p>
            <div>
              <Button size="sm" disabled={start.isPending} onClick={() => start.mutate()}>
                Retry from here
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* --- Script summary --- */}
      {script && (
        <details className="group rounded-lg border border-border bg-surface-1" open={scenes.length === 0}>
          <summary className="cursor-pointer list-none p-4 text-sm font-semibold">
            Script — {script.selected_title}
            <span className="ml-2 font-normal text-muted">
              ~{script.estimated_duration_seconds ?? "?"}s · v{script.version}
            </span>
          </summary>
          <div className="flex flex-col gap-3 p-4 pt-0 text-sm">
            {script.hook && (
              <p>
                <span className="text-muted">Hook: </span>
                {script.hook}
              </p>
            )}
            <p className="whitespace-pre-wrap text-muted">{script.full_narration}</p>
          </div>
        </details>
      )}

      {/* --- Storyboard grid --- */}
      {scenes.length > 0 && (
        <section className="flex flex-col gap-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">Storyboard</h2>
            <span className="text-xs text-muted">{scenes.length} scenes</span>
          </div>

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {scenes.map((scene) => (
              <SceneCard
                key={scene.id}
                scene={scene}
                projectId={id}
                editable={checkpoint === "storyboard"}
              />
            ))}
          </div>

          {checkpoint === "storyboard" && (
            <div className="flex flex-col gap-3 rounded-lg border border-border bg-surface-1 p-4">
              <div className="flex flex-wrap items-center gap-3">
                <label className="text-sm text-muted">Visual style</label>
                <select
                  className="h-9 rounded-md border border-border bg-surface-1 px-2 text-sm"
                  value={project.visual_style}
                  disabled={updateProject.isPending || regenAll.isPending || running}
                  onChange={(e) =>
                    updateProject.mutate({ visual_style: e.target.value as typeof project.visual_style })
                  }
                >
                  {VISUAL_STYLES.map((s) => (
                    <option key={s.value} value={s.value}>
                      {s.label}
                    </option>
                  ))}
                </select>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={regenAll.isPending || running}
                  onClick={() => regenAll.mutate()}
                >
                  {regenAll.isPending || running ? "Regenerating…" : "Regenerate all images"}
                </Button>
              </div>
              <div className="flex flex-wrap items-center gap-3 border-t border-border pt-3">
                <p className="flex-1 text-sm text-muted">
                  Review the storyboard — regenerate or edit any scene. When it looks right,
                  continue to narration and rendering.
                </p>
                <Button disabled={cont.isPending || running} onClick={() => cont.mutate()}>
                  {cont.isPending ? "Continuing…" : "Looks good — continue"}
                </Button>
              </div>
            </div>
          )}
        </section>
      )}

      {/* --- Review checkpoint: preflight + video --- */}
      {checkpoint === "review" && (
        <>
          <PreflightCard projectId={id} />

          <Card>
            <CardHeader>
              <CardTitle>Your video</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
              {latestRender?.status === "completed" && latestRender.output_url ? (
                <>
                  <video
                    controls
                    src={latestRender.output_url}
                    className="w-full rounded border border-border"
                  />
                  <div className="flex flex-wrap gap-3">
                    <a href={latestRender.output_url} download>
                      <Button size="sm">Download MP4</Button>
                    </a>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => revise.mutate()}
                      disabled={revise.isPending}
                    >
                      Edit storyboard
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => render.mutate()}
                      disabled={render.isPending || running}
                    >
                      Re-render
                    </Button>
                  </div>
                </>
              ) : latestRender?.status === "failed" ? (
                <div className="flex flex-col gap-2">
                  <p className="text-sm text-danger">
                    {latestRender.failure_reason ?? "Render failed."}
                  </p>
                  <Button size="sm" onClick={() => render.mutate()} disabled={render.isPending}>
                    Retry render
                  </Button>
                </div>
              ) : (
                <div className="flex flex-col gap-2">
                  <p className="text-sm text-muted">Rendering your video…</p>
                  <Progress value={latestRender?.progress ?? 5} />
                </div>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
