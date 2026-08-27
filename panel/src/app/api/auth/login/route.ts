import { NextResponse } from "next/server";

import { API_BASE_URL } from "@/lib/config";
import { setSession } from "@/lib/session";

export async function POST(request: Request) {
  const credentials = await request.json();

  const response = await fetch(`${API_BASE_URL}/auth/staff/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(credentials),
    cache: "no-store",
  });

  const body = await response.json().catch(() => null);
  if (!response.ok) {
    return NextResponse.json(body ?? { detail: "Login failed." }, { status: response.status });
  }

  await setSession({ access: body.access, refresh: body.refresh });
  return NextResponse.json({ user: body.user });
}
