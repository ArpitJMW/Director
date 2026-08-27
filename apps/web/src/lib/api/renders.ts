import { useQuery } from "@tanstack/react-query";
import type { VideoRender } from "@clipify/types";
import { apiFetch } from "./client";
import { projectKeys } from "./projects";

export function useProjectRenders(projectId: string) {
  return useQuery({
    queryKey: [...projectKeys.detail(projectId), "renders"] as const,
    queryFn: () =>
      apiFetch<{ renders: VideoRender[] }>(`/projects/${projectId}/renders`).then(
        (r) => r.renders,
      ),
    refetchInterval: (query) =>
      query.state.data?.some((r) => ["queued", "rendering", "uploading"].includes(r.status))
        ? 3000
        : false,
  });
}
