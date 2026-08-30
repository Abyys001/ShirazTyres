import { NextResponse } from "next/server";

import { API_BASE_URL } from "@/lib/config";
import { setSession } from "@/lib/session";

/**
 * Google sign-in. The browser gets an ID token from Google and hands it here; the API
 * verifies the signature itself, so a client-claimed email is never trusted (4.1).
 */
export async function POST(request: Request) {
  const body = await request.json();

  const response = await fetch(`${API_BASE_URL}/auth/customer/google`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ id_token: body.id_token }),
    cache: "no-store",
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    return NextResponse.json(payload ?? { detail: "Sign-in failed." }, { status: response.status });
  }

  await setSession({ access: payload.access, refresh: payload.refresh });
  return NextResponse.json({ customer: payload.customer, is_new_customer: payload.is_new_customer });
}
