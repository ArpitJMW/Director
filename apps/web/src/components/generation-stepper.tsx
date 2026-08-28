"use client";

import { Progress, PulseDot, cn } from "@clipify/ui";
import type { GenerationJob, GenerationStage, Project } from "@clipify/types";

const STAGES: { key: GenerationStage; label: string; checkpointAfter?: boolean }[] = [
  { key: "script", label: "Script" },
  { key: "storyboard", label: "Storyboard" },
  { key: "assets", label: "Visuals", checkpointAfter: true },
  { key: "voice", label: "Voice & captions" },
  { key: "preflight", label: "Preflight" },
  { key: "render", label: "Render", checkpointAfter: true },
];

type State = "pending" | "active" | "done" | "failed";

function stageState(
  key: GenerationStage,
  jobs: GenerationJob[],
  project: Project,
): State {
  const job = jobs.filter((j) => j.stage === key && !j.scene_id).at(-1);
  if (job?.status === "succeeded") return "done";
  if (job?.status === "failed") return "failed";
  if (job?.active || project.pipeline.active_stage === key) return "active";
  return "pending";
}

export function GenerationStepper({
  project,
  jobs,
}: {
  project: Project;
  jobs: GenerationJob[];
}) {
  const states = STAGES.map((s) => ({ ...s, state: stageState(s.key, jobs, project) }));
  const doneCount = states.filter((s) => s.state === "done").length;
  const pct = Math.round((doneCount / STAGES.length) * 100);
  const failed = states.some((s) => s.state === "failed") || project.status === "failed";

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xs text-muted">
        <span>
          {failed
            ? "Paused — needs attention"
            : project.pipeline.checkpoint
              ? "Waiting for your review"
              : doneCount === STAGES.length
                ? "All stages complete"
                : "Generating…"}
        </span>
        <span>{pct}%</span>
      </div>
      <Progress value={pct} />

      <ol className="mt-1 flex flex-col gap-0.5">
        {states.map((s, i) => (
          <li
            key={s.key}
            className={cn(
              "flex items-center gap-3 rounded-md px-2 py-1.5 text-sm transition-colors duration-200",
              s.state === "active" && "bg-accent/10",
            )}
          >
            <span className="flex h-5 w-5 shrink-0 items-center justify-center">
              {s.state === "done" && (
                <span className="flex h-5 w-5 items-center justify-center rounded-full bg-success text-[11px] text-white transition-transform duration-200">
                  ✓
                </span>
              )}
              {s.state === "failed" && (
                <span className="flex h-5 w-5 items-center justify-center rounded-full bg-danger text-[11px] text-white">
                  !
                </span>
              )}
              {s.state === "active" && <PulseDot />}
              {s.state === "pending" && (
                <span className="h-2 w-2 rounded-full border border-border" />
              )}
            </span>

            <span
              className={cn(
                "transition-colors duration-200",
                s.state === "done" && "text-muted",
                s.state === "active" && "font-medium text-foreground",
                s.state === "pending" && "text-muted",
                s.state === "failed" && "font-medium text-danger",
              )}
            >
              {s.label}
            </span>

            {s.checkpointAfter && project.pipeline.checkpoint === (i < 3 ? "storyboard" : "review") && (
              <span className="ml-auto rounded-full bg-warning/20 px-2 py-0.5 text-[10px] font-medium text-warning-foreground">
                review
              </span>
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}
