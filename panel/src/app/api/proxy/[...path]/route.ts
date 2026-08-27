import { NextResponse } from "next/server";

import { apiFetch } from "@/lib/server-api";

type Context = { params: Promise<{ path: string[] }> };

/**
 * Single pass-through to Django for client components. Keeping it here means the
 * access token stays in an httpOnly cookie and never reaches the browser.
 */
async function forward(request: Request, context: Context) {
  const { path } = await context.params;
  const search = new URL(request.url).search;
  const body = ["GET", "HEAD"].includes(request.method) ? undefined : await request.text();

  const response = await apiFetch(`/${path.join("/")}${search}`, {
    method: request.method,
    body: body || undefined,
  });

  const text = await response.text();
  if (!text) return new NextResponse(null, { status: response.status });

  return new NextResponse(text, {
    status: response.status,
    headers: { "Content-Type": response.headers.get("Content-Type") ?? "application/json" },
  });
}

export const GET = forward;
export const POST = forward;
export const PATCH = forward;
export const PUT = forward;
export const DELETE = forward;
