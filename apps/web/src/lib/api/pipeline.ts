import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { GenerationJob, Project, UpdateSceneInput, SceneResource } from "@clipify/types";
import { apiFetch } from "./client";
import { projectKeys } from "./projects";

export const jobKeys = {
  list: (projectId: string) => [...projectKeys.detail(projectId), "jobs"] as const,
};

export function useProjectJobs(projectId: string, { poll = true }: { poll?: boolean } = {}) {
  return useQuery({
    queryKey: jobKeys.list(projectId),
    queryFn: () =>
      apiFetch<{ jobs: GenerationJob[] }>(`/projects/${projectId}/jobs`).then((r) => r.jobs),
    refetchInterval: (query) =>
      poll && query.state.data?.some((job) => job.active) ? 1500 : false,
  });
}

function invalidateProject(qc: ReturnType<typeof useQueryClient>, projectId: string) {
  qc.invalidateQueries({ queryKey: jobKeys.list(projectId) });
  qc.invalidateQueries({ queryKey: projectKeys.detail(projectId) });
  qc.invalidateQueries({ queryKey: projectKeys.scenes(projectId) });
}

/** Kick off the auto-running pipeline from the beginning. */
export function useStartPipeline(projectId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      apiFetch<{ job: GenerationJob; project: Project }>(
        `/projects/${projectId}/pipeline/start`,
        { method: "POST" },
      ),
    onSuccess: () => invalidateProject(qc, projectId),
  });
}

function usePipelineAction(
  projectId: string,
  action: "continue" | "revise" | "stop" | "restart",
) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      apiFetch<{ project: Project }>(`/projects/${projectId}/pipeline/${action}`, {
        method: "POST",
      }),
    onSuccess: () => invalidateProject(qc, projectId),
  });
}

/** Approve a review checkpoint and resume the pipeline. */
export const useContinuePipeline = (id: string) => usePipelineAction(id, "continue");

/** Send a finished project back to the storyboard checkpoint for edits. */
export const useRevisePipeline = (id: string) => usePipelineAction(id, "revise");

/** Halt an in-flight generation run (keeps whatever was generated so far). */
export const useStopPipeline = (id: string) => usePipelineAction(id, "stop");

/** Discard everything and run the whole pipeline again from the top. */
export const useRestartPipeline = (id: string) => usePipelineAction(id, "restart");

function useStageMutation(projectId: string, stagePath: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      apiFetch<{ job: GenerationJob; project: Project }>(
        `/projects/${projectId}/${stagePath}`,
        { method: "POST" },
      ),
    onSuccess: () => invalidateProject(qc, projectId),
  });
}

// Manual / re-run triggers (kept for regeneration from a checkpoint).
export const useGenerateStoryboard = (id: string) => useStageMutation(id, "storyboard/generate");
export const useGenerateAssets = (id: string) => useStageMutation(id, "assets/generate");
export const useRegenerateAllImages = (id: string) => useStageMutation(id, "assets/generate?force=true");
export const useRenderVideo = (id: string) => useStageMutation(id, "render");

export function useRegenerateSceneAsset(projectId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (sceneId: string) =>
      apiFetch<{ job: GenerationJob }>(`/scenes/${sceneId}/assets/regenerate`, {
        method: "POST",
      }),
    onSuccess: () => invalidateProject(qc, projectId),
  });
}

export function useUpdateScene(projectId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ sceneId, input }: { sceneId: string; input: UpdateSceneInput }) =>
      apiFetch<{ scene: SceneResource }>(`/scenes/${sceneId}`, {
        method: "PATCH",
        body: JSON.stringify({ scene: input }),
      }).then((r) => r.scene),
    onSuccess: () => qc.invalidateQueries({ queryKey: projectKeys.scenes(projectId) }),
  });
}
