import type { ApiError } from "@clipify/types";

export class ApiClientError extends Error {
  status: number;
  payload: ApiError | null;

  constructor(status: number, payload: ApiError | null) {
    super(payload?.message ?? payload?.messages?.join(", ") ?? `Request failed (${status})`);
    this.name = "ApiClientError";
    this.status = status;
    this.payload = payload;
  }
}

/**
 * Client-side fetch. Hits the same-origin Next proxy (`/api/v1/...`), which
 * attaches the JWT cookie. `path` is relative to `/api/v1`.
 */
export async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`/api/v1${path}`, {
    ...init,
    headers: {
      Accept: "application/json",
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers,
    },
  });

  if (res.status === 204) return undefined as T;

  const text = await res.text();
  const data = text ? JSON.parse(text) : null;

  if (!res.ok) {
    throw new ApiClientError(res.status, data as ApiError | null);
  }
  return data as T;
}

export function apiHeaders(res: Response) {
  return {
    total: Number(res.headers.get("X-Total-Count") ?? 0),
    page: Number(res.headers.get("X-Page") ?? 1),
    totalPages: Number(res.headers.get("X-Total-Pages") ?? 1),
  };
}
