import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

import { REFRESH_COOKIE } from "@/lib/config";

/** Signed-in surfaces: requesting a call-out and following one (specification 4.1, 4.6). */
const PRIVATE_PATHS = ["/request", "/jobs", "/garage", "/account"];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const signedIn = Boolean(request.cookies.get(REFRESH_COOKIE)?.value);

  if (!signedIn && PRIVATE_PATHS.some((path) => pathname.startsWith(path))) {
    const signIn = new URL("/sign-in", request.url);
    signIn.searchParams.set("next", pathname);
    return NextResponse.redirect(signIn);
  }

  if (signedIn && pathname === "/sign-in") {
    return NextResponse.redirect(new URL("/request", request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
