import { NextResponse } from "next/server";

import { API_BASE_URL } from "@/lib/config";

/** Sends the sign-in code. Anonymous — there is no session yet (specification 4.1). */
export async function POST(request: Request) {
  const body = await request.json();

  const response = await fetch(`${API_BASE_URL}/auth/otp/request`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phone: body.phone, purpose: "login" }),
    cache: "no-store",
  });

  const payload = await response.json().catch(() => null);
  return NextResponse.json(payload ?? { detail: "Could not send a code." }, { status: response.status });
}
