import "server-only";

import { API_BASE_URL } from "./config";
import { getTokens, setSession } from "./session";

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly errors: Record<string, string[]> = {},
  ) {
    super(message);
  }
}

async function request(path: string, init: RequestInit, access: string | null) {
  const headers = new Headers(init.headers);
  if (access) headers.set("Authorization", `Bearer ${access}`);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");

  return fetch(`${API_BASE_URL}${path}`, { ...init, headers, cache: "no-store" });
}

/**
 * Server-side call to the Django API. A 401 triggers one refresh attempt; anything
 * still failing is the caller's problem to surface.
 */
export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const { access, refresh } = await getTokens();
  let response = await request(path, init, access);

  if (response.status === 401 && refresh) {
    const refreshed = await fetch(`${API_BASE_URL}/auth/staff/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh }),
      cache: "no-store",
    });

    if (refreshed.ok) {
      const tokens = (await refreshed.json()) as { access: string; refresh: string };
      await setSession(tokens);
      response = await request(path, init, tokens.access);
    }
  }

  return response;
}

export async function apiJson<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await apiFetch(path, init);
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;

  if (!response.ok) {
    throw new ApiError(body?.detail ?? "Request failed.", response.status, body?.errors ?? {});
  }
  return body as T;
}
