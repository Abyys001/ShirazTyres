"use client";

import type { ApiErrorBody } from "@/types/api";

export class ClientApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly errors: Record<string, string[]> = {},
  ) {
    super(message);
  }
}

/** Browser-side calls go to the Next proxy, which holds the tokens. */
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`/api/proxy${path}`, {
    ...init,
    headers: {
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers,
    },
  });

  const text = await response.text();
  const body = text ? (JSON.parse(text) as ApiErrorBody & Record<string, unknown>) : null;

  if (!response.ok) {
    throw new ClientApiError(body?.detail ?? "Request failed.", response.status, body?.errors ?? {});
  }
  return body as T;
}

export function fieldError(error: unknown, field: string): string | null {
  if (error instanceof ClientApiError) {
    const messages = error.errors?.[field];
    if (messages?.length) return messages[0];
  }
  return null;
}
