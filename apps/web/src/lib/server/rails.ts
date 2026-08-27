import { cookies } from "next/headers";
import { API_URL, TOKEN_COOKIE } from "@/lib/config";

/**
 * Server-side fetch to the Rails API. Attaches the JWT from the httpOnly cookie
 * as a Bearer token. Use only in route handlers / server components.
 */
export async function railsFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const token = (await cookies()).get(TOKEN_COOKIE)?.value;

  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (token) headers.set("Authorization", `Bearer ${token}`);

  return fetch(`${API_URL}${path}`, { ...init, headers, cache: "no-store" });
}

export async function currentUser(): Promise<{ id: string; name: string; email: string } | null> {
  const res = await railsFetch("/api/v1/me");
  if (!res.ok) return null;
  const body = (await res.json()) as { user: { id: string; name: string; email: string } };
  return body.user;
}
