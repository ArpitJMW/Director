"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useRef } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@clipify/ui";
import { useProject, useProjectScenes, projectKeys } from "@/lib/api/projects";
import { useGenerateScript, useProjectJobs } from "@/lib/api/pipeline";
import { ProjectStatusBadge } from "@/components/project-status-badge";
import { PipelineProgress } from "@/components/pipeline-progress";

export default function ProjectPage() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();
  const { data: project, isLoading, isError, error } = useProject(id);
  const { data: scenes } = useProjectScenes(id);
  const { data: jobs } = useProjectJobs(id);
  const generateScript = useGenerateScript(id);

  const scriptJob = jobs?.find((j) => j.stage === "script");
  const scriptRunning = Boolean(scriptJob?.active);

  // When a job finishes, refresh the project so current_script / status update.
  const wasRunning = useRef(false);
  useEffect(() => {
    if (wasRunning.current && !scriptRunning) {
      qc.invalidateQueries({ queryKey: projectKeys.detail(id) });
    }
    wasRunning.current = scriptRunning;
  }, [scriptRunning, id, qc]);

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
          {!scenes?.length && (
            <p className="text-sm text-muted">
              No scenes yet — they appear after storyboard generation.
            </p>
          )}
          <ol className="flex flex-col gap-3">
            {scenes?.map((s) => (
              <li key={s.id} className="rounded-md border border-border p-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">
                    {s.scene.id} · {s.scene.visual_type.replace(/_/g, " ")}
                  </span>
                  <span className="text-xs text-muted">{s.scene.duration}s</span>
                </div>
                {s.scene.narration && (
                  <p className="mt-1 text-sm text-muted">{s.scene.narration}</p>
                )}
              </li>
            ))}
          </ol>
        </CardContent>
      </Card>
    </div>
  );
}
