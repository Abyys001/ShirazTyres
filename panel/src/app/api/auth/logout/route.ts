import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

import { clearSession } from "@/lib/session";

export async function POST() {
  await clearSession();
  return NextResponse.json({ ok: true });
}

/**
 * Server Components cannot clear cookies, so a layout that finds the session dead
 * redirects here instead of straight to /login — otherwise the middleware would see
 * the stale refresh cookie and bounce the request back into the panel forever.
 */
export async function GET(request: NextRequest) {
  await clearSession();

  const login = new URL("/login", request.url);
  const next = request.nextUrl.searchParams.get("next");
  if (next?.startsWith("/")) login.searchParams.set("next", next);

  return NextResponse.redirect(login);
}
