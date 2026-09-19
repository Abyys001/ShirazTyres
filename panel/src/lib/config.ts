export const API_BASE_URL = (
  process.env.API_BASE_URL ?? process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000/api/v1"
).replace(/\/$/, "");

export const ACCESS_COOKIE = "st_access";
export const REFRESH_COOKIE = "st_refresh";

export const ACCESS_MAX_AGE = 60 * 30;
export const REFRESH_MAX_AGE = 60 * 60 * 24 * 30;

/**
 * Whether the session cookies are marked `Secure`.
 *
 * This tracks the transport, not the build. It used to be
 * `NODE_ENV === "production"`, which conflated "built for production" with
 * "served over TLS" — and they are not the same thing. A production build put
 * behind plain http sets `Secure` on the session cookies, the browser then
 * declines to send them back, and every request arrives signed out: the panel
 * bounces to /login and stays there, with nothing in any log to say why.
 *
 * So it is asked directly. Default is still the build mode, so nothing changes
 * for a deployment that has not thought about it; a stack published over plain
 * http sets `COOKIE_SECURE=false` and says so to itself in `.env`.
 *
 * Read through a literal `process.env.X` rather than a lookup, because the
 * middleware runs on the edge runtime where these are inlined at build time.
 */
const COOKIE_SECURE =
  (process.env.COOKIE_SECURE ?? (process.env.NODE_ENV === "production" ? "true" : "false"))
    .toLowerCase() === "true";

/** Shared by the session helpers and the middleware, which both write these cookies. */
export const COOKIE_OPTIONS = {
  httpOnly: true,
  sameSite: "lax" as const,
  secure: COOKIE_SECURE,
  path: "/",
};
