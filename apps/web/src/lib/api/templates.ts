import { useQuery } from "@tanstack/react-query";
import type { Template } from "@clipify/types";
import { apiFetch } from "./client";

export const templateKeys = {
  all: ["templates"] as const,
  list: () => [...templateKeys.all, "list"] as const,
};

export function useTemplates() {
  return useQuery({
    queryKey: templateKeys.list(),
    queryFn: () => apiFetch<{ templates: Template[] }>("/templates").then((r) => r.templates),
    staleTime: 5 * 60 * 1000,
  });
}
