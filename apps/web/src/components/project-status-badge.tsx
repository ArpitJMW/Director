import { Badge } from "@clipify/ui";
import type { PipelineCheckpoint, ProjectStatus } from "@clipify/types";

const TONE: Record<ProjectStatus, Parameters<typeof Badge>[0]["tone"]> = {
  draft: "neutral",
  researching: "info",
  script_generating: "info",
  storyboarding: "info",
  generating_assets: "info",
  generating_voice: "info",
  generating_captions: "info",
  rendering: "info",
  quality_check: "info",
  completed: "success",
  failed: "danger",
  cancelled: "neutral",
};

export function ProjectStatusBadge({
  status,
  checkpoint,
}: {
  status: ProjectStatus;
  /** Task 4.3 Part 5: the project's AASM status stays "rendering" for as long
   *  as the project sits at the "review" checkpoint — that status legitimately
   *  covers both "actively rendering" AND "rendered, waiting on you" (the
   *  project isn't AASM-"completed" until the user approves past review), so
   *  the raw status alone reads as still-in-progress even once the render has
   *  actually finished and is sitting there playable. Passing the checkpoint
   *  lets the badge distinguish those two without touching the state machine. */
  checkpoint?: PipelineCheckpoint | null;
}) {
  if (status === "rendering" && checkpoint === "review") {
    return <Badge tone="success">ready for review</Badge>;
  }
  return <Badge tone={TONE[status]}>{status.replace(/_/g, " ")}</Badge>;
}
