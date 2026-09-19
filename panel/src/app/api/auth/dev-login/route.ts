import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

import { API_BASE_URL } from "@/lib/config";
import { setSession } from "@/lib/session";

/**
 * The seeded-account buttons on /login, as a plain form POST.
 *
 * /api/auth/login is fetched from the browser and so needs the page to have
 * hydrated first. On a dev build served over a network that takes a moment,
 * and a click landing before it does nothing at all — the button looks broken
 * when it is only early. This route does the same work without any client
 * JavaScript: the browser posts the form, the cookies are set here, and the
 * response is a redirect into the panel.
 *
 * Development only, like the buttons themselves.
 */
export async function POST(request: NextRequest) {
  if (process.env.NODE_ENV === "production") {
    return new NextResponse("Not found", { status: 404 });
  }

  const form = await request.formData();
  const email = String(form.get("email") ?? "");
  const password = String(form.get("password") ?? "");
  const next = String(form.get("next") ?? "");

  const response = await fetch(`${API_BASE_URL}/auth/staff/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
    cache: "no-store",
  });

  const body = await response.json().catch(() => null);
  if (!response.ok) {
    const detail = body?.errors?.detail?.[0] ?? body?.detail ?? "Could not sign in.";
    const query = new URLSearchParams({ error: detail });
    if (next.startsWith("/")) query.set("next", next);
    return seeOther(`/login?${query}`);
  }

  await setSession({ access: body.access, refresh: body.refresh });

  // Only a path, never an absolute URL from the form: an open redirect on the
  // sign-in route is worth avoiding even in a development-only one.
  return seeOther(next.startsWith("/") && !next.startsWith("//") ? next : "/jobs");
}

/**
 * A relative Location, and deliberately not `NextResponse.redirect`, which
 * needs an absolute URL and would build it from `request.url` — inside the
 * container that is http://localhost:3000, so the browser would be sent to
 * its own localhost rather than back to the panel.
 *
 * 303 rather than 302: the browser must follow this with a GET and not repeat
 * the POST.
 */
function seeOther(path: string) {
  return new NextResponse(null, { status: 303, headers: { Location: path } });
}
