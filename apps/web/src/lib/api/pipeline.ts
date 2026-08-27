import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { GenerationJob, Project } from "@clipify/types";
import { apiFetch } from "./client";
import { projectKeys } from "./projects";

export const jobKeys = {
  list: (projectId: string) => [...projectKeys.detail(projectId), "jobs"] as const,
};

export function useProjectJobs(projectId: string) {
  return useQuery({
    queryKey: jobKeys.list(projectId),
    queryFn: () =>
      apiFetch<{ jobs: GenerationJob[] }>(`/projects/${projectId}/jobs`).then((r) => r.jobs),
    // Poll while any job is active (spec §30).
    refetchInterval: (query) =>
      query.state.data?.some((job) => job.active) ? 2000 : false,
  });
}

function useStageMutation(projectId: string, stagePath: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      apiFetch<{ job: GenerationJob; project: Project }>(
        `/projects/${projectId}/${stagePath}`,
        { method: "POST" },
      ),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: jobKeys.list(projectId) });
      qc.invalidateQueries({ queryKey: projectKeys.detail(projectId) });
    },
  });
}

export function useGenerateScript(projectId: string) {
  return useStageMutation(projectId, "script/generate");
}

export function useGenerateStoryboard(projectId: string) {
  return useStageMutation(projectId, "storyboard/generate");
}

export function useGenerateAssets(projectId: string) {
  return useStageMutation(projectId, "assets/generate");
}

export function useRegenerateSceneAsset(projectId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (sceneId: string) =>
      apiFetch<{ job: GenerationJob }>(`/scenes/${sceneId}/assets/regenerate`, {
        method: "POST",
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: jobKeys.list(projectId) }),
  });
}
