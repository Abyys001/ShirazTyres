import { NextResponse } from "next/server";

import { API_BASE_URL } from "@/lib/config";
import { getTokens, setSession } from "@/lib/session";

/**
 * Seconds of life left on a JWT, or null when it cannot be read.
 *
 * Only the `exp` claim is read, and only to decide whether to bother refreshing
 * — the signature is the API's business, and nothing here trusts the contents.
 */
function secondsLeft(token: string): number | null {
  try {
    const payload = token.split(".")[1];
    if (!payload) return null;
    const json = Buffer.from(payload.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString();
    const exp = (JSON.parse(json) as { exp?: number }).exp;
    return typeof exp === "number" ? exp - Math.floor(Date.now() / 1000) : null;
  } catch {
    return null;
  }
}

/**
 * A socket handshake is refused outright by an expired token — there is no
 * retry-with-a-fresh-one inside the connection the way the REST client has.
 * A minute of headroom, because this token has to outlive the handshake.
 */
const MIN_LIFE_SECONDS = 60;

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

  // The access cookie and the token inside it expire at about the same moment,
  // but not at the same moment — the cookie is written a round trip after the
  // token is minted. Handing back the seconds in between produced a handshake
  // refused with 4401, a reconnect, and another refusal, indefinitely: the
  // panel said "Reconnecting" and never stopped, because the only thing that
  // would have fixed it was the refresh this branch skipped.
  if (access && (secondsLeft(access) ?? Number.POSITIVE_INFINITY) > MIN_LIFE_SECONDS) {
    return NextResponse.json({ token: access });
  }

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

  // The refresh failed but the access token is merely short of headroom rather
  // than dead. Worth one attempt: a socket that lasts ten minutes beats none.
  if (access && (secondsLeft(access) ?? 0) > 0) {
    return NextResponse.json({ token: access });
  }

  return NextResponse.json({ detail: "Not signed in." }, { status: 401 });
}
