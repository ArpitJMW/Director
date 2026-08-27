import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { GenerationJob, PreflightReport } from "@clipify/types";
import { apiFetch, ApiClientError } from "./client";
import { projectKeys } from "./projects";
import { jobKeys } from "./pipeline";

const preflightKey = (projectId: string) =>
  [...projectKeys.detail(projectId), "preflight"] as const;

export function usePreflight(projectId: string) {
  return useQuery({
    queryKey: preflightKey(projectId),
    queryFn: async (): Promise<PreflightReport | null> => {
      try {
        return await apiFetch<{ preflight: PreflightReport }>(
          `/projects/${projectId}/preflight`,
        ).then((r) => r.preflight);
      } catch (err) {
        if (err instanceof ApiClientError && err.status === 404) return null;
        throw err;
      }
    },
  });
}

export function useGeneratePreflight(projectId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      apiFetch<{ job: GenerationJob }>(`/projects/${projectId}/preflight/generate`, {
        method: "POST",
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: jobKeys.list(projectId) });
      qc.invalidateQueries({ queryKey: preflightKey(projectId) });
    },
  });
}

export function useAcknowledgePreflight(projectId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      apiFetch<{ preflight: PreflightReport }>(
        `/projects/${projectId}/preflight/acknowledge`,
        { method: "POST" },
      ).then((r) => r.preflight),
    onSuccess: (report) => qc.setQueryData(preflightKey(projectId), report),
  });
}
