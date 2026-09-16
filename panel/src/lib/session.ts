import "server-only";

import { cookies } from "next/headers";

import {
  ACCESS_COOKIE,
  ACCESS_MAX_AGE,
  COOKIE_OPTIONS,
  REFRESH_COOKIE,
  REFRESH_MAX_AGE,
} from "./config";

export interface TokenPair {
  access: string;
  refresh: string;
}

/** Tokens never reach client JavaScript — every browser call goes through /api/proxy. */
export async function setSession({ access, refresh }: TokenPair) {
  const jar = await cookies();
  jar.set(ACCESS_COOKIE, access, { ...COOKIE_OPTIONS, maxAge: ACCESS_MAX_AGE });
  jar.set(REFRESH_COOKIE, refresh, { ...COOKIE_OPTIONS, maxAge: REFRESH_MAX_AGE });
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
