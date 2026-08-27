import "server-only";

import { cookies } from "next/headers";

import { ACCESS_COOKIE, REFRESH_COOKIE } from "./config";

const BASE_COOKIE = {
  httpOnly: true,
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
  path: "/",
};

export interface TokenPair {
  access: string;
  refresh: string;
}

/** Tokens never reach client JavaScript — every browser call goes through /api/proxy. */
export async function setSession({ access, refresh }: TokenPair) {
  const jar = await cookies();
  jar.set(ACCESS_COOKIE, access, { ...BASE_COOKIE, maxAge: 60 * 30 });
  jar.set(REFRESH_COOKIE, refresh, { ...BASE_COOKIE, maxAge: 60 * 60 * 24 * 30 });
}

export async function clearSession() {
  const jar = await cookies();
  jar.delete(ACCESS_COOKIE);
  jar.delete(REFRESH_COOKIE);
}

export async function getTokens() {
  const jar = await cookies();
  return {
    access: jar.get(ACCESS_COOKIE)?.value ?? null,
    refresh: jar.get(REFRESH_COOKIE)?.value ?? null,
  };
}
