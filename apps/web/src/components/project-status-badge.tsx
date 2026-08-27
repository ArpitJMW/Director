import { Badge } from "@clipify/ui";
import type { ProjectStatus } from "@clipify/types";

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

export function ProjectStatusBadge({ status }: { status: ProjectStatus }) {
  return <Badge tone={TONE[status]}>{status.replace(/_/g, " ")}</Badge>;
}
