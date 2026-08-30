import { NextResponse } from "next/server";

import { API_BASE_URL } from "@/lib/config";
import { getTokens, setSession } from "@/lib/session";

/**
 * Hands the browser a WebSocket token.
 *
 * The REST path keeps its tokens in httpOnly cookies, but a WebSocket handshake cannot
 * carry a header, so the access token has to reach client JavaScript for this one use.
 * It is short-lived by configuration (JWT_ACCESS_MINUTES) and the refresh token — the
 * one worth stealing — never leaves the cookie jar.
 */
export async function GET() {
  const { access, refresh } = await getTokens();
  if (access) return NextResponse.json({ token: access });

  if (refresh) {
    const refreshed = await fetch(`${API_BASE_URL}/auth/staff/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh }),
      cache: "no-store",
    });
    if (refreshed.ok) {
      const tokens = (await refreshed.json()) as { access: string; refresh: string };
      await setSession(tokens);
      return NextResponse.json({ token: tokens.access });
    }
  }

  return NextResponse.json({ detail: "Not signed in." }, { status: 401 });
}
