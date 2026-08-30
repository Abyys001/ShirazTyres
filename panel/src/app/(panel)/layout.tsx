import { redirect } from "next/navigation";

import { NavBar } from "@/components/nav-bar";
import { apiJson } from "@/lib/server-api";
import type { StaffUser } from "@/types/api";

export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  let user: StaffUser;
  try {
    user = await apiJson<StaffUser>("/auth/staff/me");
  } catch {
    redirect("/login");
  }

  return (
    <div className="min-h-screen">
      <NavBar user={user} />
      <main className="mx-auto max-w-7xl px-4 py-6">{children}</main>
    </div>
  );
}
