import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

import {
  ACCESS_COOKIE,
  ACCESS_MAX_AGE,
  API_BASE_URL,
  COOKIE_OPTIONS,
  REFRESH_COOKIE,
  REFRESH_MAX_AGE,
} from "@/lib/config";

const PUBLIC_PATHS = ["/login", "/api/auth/login", "/api/auth/logout"];

interface TokenPair {
  access: string;
  refresh: string;
}

async function renew(refresh: string): Promise<TokenPair | null> {
  try {
    const response = await fetch(`${API_BASE_URL}/auth/staff/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh }),
      cache: "no-store",
    });
    return response.ok ? ((await response.json()) as TokenPair) : null;
  } catch {
    return null;
  }
}

function toLogin(request: NextRequest) {
  const login = new URL("/login", request.url);
  login.searchParams.set("next", request.nextUrl.pathname);
  return NextResponse.redirect(login);
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const isPublic = PUBLIC_PATHS.some((path) => pathname.startsWith(path));
  const refresh = request.cookies.get(REFRESH_COOKIE)?.value;

  if (!refresh) return isPublic ? NextResponse.next() : toLogin(request);

  // The access cookie expires half an hour into a thirty-day session, and a Server
  // Component render cannot write cookies — so renewal has to happen here, before
  // the render, or every page would bounce back to /login with a live session.
  if (!request.cookies.get(ACCESS_COOKIE)?.value) {
    const tokens = await renew(refresh);

    if (!tokens) {
      const response = isPublic ? NextResponse.next() : toLogin(request);
      response.cookies.delete(ACCESS_COOKIE);
      response.cookies.delete(REFRESH_COOKIE);
      return response;
    }

    request.cookies.set(ACCESS_COOKIE, tokens.access);
    request.cookies.set(REFRESH_COOKIE, tokens.refresh);

    const response =
      pathname === "/login"
        ? NextResponse.redirect(new URL("/jobs", request.url))
        : NextResponse.next({ request });
    response.cookies.set(ACCESS_COOKIE, tokens.access, {
      ...COOKIE_OPTIONS,
      maxAge: ACCESS_MAX_AGE,
    });
    response.cookies.set(REFRESH_COOKIE, tokens.refresh, {
      ...COOKIE_OPTIONS,
      maxAge: REFRESH_MAX_AGE,
    });
    return response;
  }

  if (pathname === "/login") return NextResponse.redirect(new URL("/jobs", request.url));

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
