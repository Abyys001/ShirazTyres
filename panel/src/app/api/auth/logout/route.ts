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

  const next = request.nextUrl.searchParams.get("next");
  const query = next?.startsWith("/") ? `?${new URLSearchParams({ next })}` : "";

  // A relative Location, not `NextResponse.redirect`: that needs an absolute
  // URL and builds it from `request.url`, which inside the container is
  // http://localhost:3000 — it would send the browser to its own localhost.
  return new NextResponse(null, { status: 307, headers: { Location: `/login${query}` } });
}
