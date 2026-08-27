import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import type { User } from "@clipify/types";

export const sessionKey = ["session"] as const;

async function postJson(path: string, body: unknown) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const message =
      data?.messages?.join(", ") ?? data?.error ?? `Request failed (${res.status})`;
    throw new Error(message);
  }
  return data;
}

export function useSession() {
  return useQuery({
    queryKey: sessionKey,
    queryFn: async (): Promise<User | null> => {
      const res = await fetch("/api/auth/session");
      const data = (await res.json()) as { user: User | null };
      return data.user;
    },
    staleTime: 60 * 1000,
  });
}

export function useSignIn() {
  const qc = useQueryClient();
  const router = useRouter();
  return useMutation({
    mutationFn: (input: { email: string; password: string }) =>
      postJson("/api/auth/sign-in", input),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: sessionKey });
      router.push("/dashboard");
    },
  });
}

export function useSignUp() {
  const qc = useQueryClient();
  const router = useRouter();
  return useMutation({
    mutationFn: (input: { name: string; email: string; password: string }) =>
      postJson("/api/auth/sign-up", input),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: sessionKey });
      router.push("/dashboard");
    },
  });
}

export function useSignOut() {
  const qc = useQueryClient();
  const router = useRouter();
  return useMutation({
    mutationFn: () => postJson("/api/auth/sign-out", {}),
    onSuccess: async () => {
      qc.clear();
      router.push("/login");
    },
  });
}
