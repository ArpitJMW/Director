import { cn } from "@clipify/ui";
import type { ProjectStatus } from "@clipify/types";

// Stage-based progress UI (spec §30).
const STAGES: { key: string; label: string; statuses: ProjectStatus[] }[] = [
  { key: "research", label: "Research", statuses: ["researching"] },
  { key: "script", label: "Script", statuses: ["script_generating"] },
  { key: "storyboard", label: "Storyboard", statuses: ["storyboarding"] },
  { key: "assets", label: "Visuals", statuses: ["generating_assets"] },
  { key: "voice", label: "Voice", statuses: ["generating_voice"] },
  { key: "captions", label: "Captions", statuses: ["generating_captions"] },
  { key: "render", label: "Rendering", statuses: ["rendering"] },
  { key: "quality", label: "Quality check", statuses: ["quality_check"] },
];

const ORDER: ProjectStatus[] = [
  "draft",
  "researching",
  "script_generating",
  "storyboarding",
  "generating_assets",
  "generating_voice",
  "generating_captions",
  "rendering",
  "quality_check",
  "completed",
];

export function PipelineProgress({ status }: { status: ProjectStatus }) {
  const currentIndex = ORDER.indexOf(status);
  const failed = status === "failed";
  const cancelled = status === "cancelled";

  return (
    <ol className="flex flex-col gap-2">
      {STAGES.map((stage) => {
        const stageIndex = ORDER.indexOf(stage.statuses[0]!);
        const active = stage.statuses.includes(status);
        const done = currentIndex > stageIndex && !failed && !cancelled;

        return (
          <li key={stage.key} className="flex items-center gap-3 text-sm">
            <span
              className={cn(
                "flex h-5 w-5 items-center justify-center rounded-full border text-[10px]",
                done && "border-success bg-success text-white",
                active && "border-accent bg-accent text-white",
                !done && !active && "border-border text-muted",
              )}
            >
              {done ? "✓" : active ? "●" : "○"}
            </span>
            <span className={cn(active ? "font-medium" : "text-muted")}>{stage.label}</span>
          </li>
        );
      })}
      {failed && <li className="text-sm text-danger">Pipeline failed — {status}</li>}
      {status === "completed" && <li className="text-sm text-success">Completed</li>}
    </ol>
  );
}
