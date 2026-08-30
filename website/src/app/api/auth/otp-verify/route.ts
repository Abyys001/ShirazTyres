import { NextResponse } from "next/server";

import { API_BASE_URL } from "@/lib/config";
import { setSession } from "@/lib/session";

export async function POST(request: Request) {
  const body = await request.json();

  const response = await fetch(`${API_BASE_URL}/auth/customer/otp/verify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    cache: "no-store",
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    return NextResponse.json(payload ?? { detail: "Sign-in failed." }, { status: response.status });
  }

  await setSession({ access: payload.access, refresh: payload.refresh });
  return NextResponse.json({ customer: payload.customer, is_new_customer: payload.is_new_customer });
}
