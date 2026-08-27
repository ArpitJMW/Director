"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@clipify/ui";
import { useProject, useProjectScenes } from "@/lib/api/projects";
import { ProjectStatusBadge } from "@/components/project-status-badge";
import { PipelineProgress } from "@/components/pipeline-progress";

export default function ProjectPage() {
  const { id } = useParams<{ id: string }>();
  const { data: project, isLoading, isError, error } = useProject(id);
  const { data: scenes } = useProjectScenes(id);

  if (isLoading) return <p className="text-sm text-muted">Loading…</p>;
  if (isError) return <p className="text-sm text-danger">{(error as Error).message}</p>;
  if (!project) return null;

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
          <div className="mt-4 flex gap-3">
            <Button
              size="sm"
              disabled
              title="Available once the AI pipeline lands (Phase 3)"
            >
              Generate script
            </Button>
            <span className="self-center text-xs text-muted">
              Generation is not wired up yet.
            </span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Storyboard</CardTitle>
        </CardHeader>
        <CardContent>
          {!scenes?.length && (
            <p className="text-sm text-muted">No scenes yet — they appear after storyboard generation.</p>
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
