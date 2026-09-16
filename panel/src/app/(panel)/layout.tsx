import { redirect } from "next/navigation";

import { LiveSync } from "@/components/live-sync";
import { NavBar, TopBar } from "@/components/nav-bar";
import { apiJson } from "@/lib/server-api";
import type { StaffUser } from "@/types/api";

export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  let user: StaffUser;
  try {
    user = await apiJson<StaffUser>("/auth/staff/me");
  } catch {
    redirect("/api/auth/logout?next=/jobs");
  }

  return (
    <div className="min-h-screen lg:grid lg:grid-cols-[15rem_minmax(0,1fr)]">
      {/* One socket for the whole panel: every page below is live without asking. */}
      <LiveSync />
      <NavBar user={user} />
      <div className="flex min-h-screen flex-col">
        <TopBar user={user} />
        <main className="mx-auto w-full max-w-[100rem] flex-1 px-4 py-6 lg:px-6">{children}</main>
      </div>
    </div>
  );
}
