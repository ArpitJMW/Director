"use client";

import Link from "next/link";
import { Button, Card, CardContent } from "@clipify/ui";
import { useProjects } from "@/lib/api/projects";
import { ProjectStatusBadge } from "@/components/project-status-badge";

export default function DashboardPage() {
  const { data: projects, isLoading, isError, error } = useProjects();

  return (
    <div className="mx-auto max-w-4xl">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Projects</h1>
        <Link href="/projects/new">
          <Button>New project</Button>
        </Link>
      </div>

      {isLoading && <p className="text-sm text-muted">Loading…</p>}
      {isError && <p className="text-sm text-danger">{(error as Error).message}</p>}

      {projects?.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
            <p className="text-muted">No projects yet.</p>
            <Link href="/projects/new">
              <Button>Create your first video</Button>
            </Link>
          </CardContent>
        </Card>
      )}

      <ul className="flex flex-col gap-3">
        {projects?.map((project) => (
          <li key={project.id}>
            <Link href={`/projects/${project.id}`}>
              <Card className="transition-colors hover:border-accent/50">
                <CardContent className="flex items-center justify-between py-4">
                  <div>
                    <p className="font-medium">{project.title}</p>
                    <p className="text-sm text-muted">
                      {project.scene_count} scene{project.scene_count === 1 ? "" : "s"} ·{" "}
                      {project.target_duration_seconds}s · {project.format.replace(/_/g, " ")}
                    </p>
                  </div>
                  <ProjectStatusBadge status={project.status} />
                </CardContent>
              </Card>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
