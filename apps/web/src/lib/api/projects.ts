import {
  useMutation,
  useQuery,
  useQueryClient,
  type UseQueryOptions,
} from "@tanstack/react-query";
import type {
  CreateProjectInput,
  Project,
  SceneResource,
  UpdateProjectInput,
} from "@clipify/types";
import { apiFetch } from "./client";

export const projectKeys = {
  all: ["projects"] as const,
  list: () => [...projectKeys.all, "list"] as const,
  detail: (id: string) => [...projectKeys.all, "detail", id] as const,
  scenes: (id: string) => [...projectKeys.all, "detail", id, "scenes"] as const,
};

export function useProjects(options?: Partial<UseQueryOptions<Project[]>>) {
  return useQuery({
    queryKey: projectKeys.list(),
    queryFn: () => apiFetch<{ projects: Project[] }>("/projects").then((r) => r.projects),
    ...options,
  });
}

export function useProject(id: string, options?: Partial<UseQueryOptions<Project>>) {
  return useQuery({
    queryKey: projectKeys.detail(id),
    queryFn: () => apiFetch<{ project: Project }>(`/projects/${id}`).then((r) => r.project),
    ...options,
  });
}

export function useProjectScenes(id: string, { poll = false }: { poll?: boolean } = {}) {
  return useQuery({
    queryKey: projectKeys.scenes(id),
    queryFn: () =>
      apiFetch<{ scenes: SceneResource[] }>(`/projects/${id}/scenes`).then((r) => r.scenes),
    refetchInterval: poll ? 2000 : false,
  });
}

export function useCreateProject() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateProjectInput) =>
      apiFetch<{ project: Project }>("/projects", {
        method: "POST",
        body: JSON.stringify({ project: input }),
      }).then((r) => r.project),
    onSuccess: () => qc.invalidateQueries({ queryKey: projectKeys.list() }),
  });
}

export function useUpdateProject(id: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: UpdateProjectInput) =>
      apiFetch<{ project: Project }>(`/projects/${id}`, {
        method: "PATCH",
        body: JSON.stringify({ project: input }),
      }).then((r) => r.project),
    onSuccess: (project) => {
      qc.setQueryData(projectKeys.detail(id), project);
      qc.invalidateQueries({ queryKey: projectKeys.list() });
    },
  });
}

export function useDeleteProject() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => apiFetch<void>(`/projects/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: projectKeys.list() }),
  });
}
