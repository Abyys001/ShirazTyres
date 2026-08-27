"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";

import type { StaffUser } from "@/types/api";

const LINKS = [
  { href: "/bookings", label: "Call-outs" },
  { href: "/drivers", label: "Drivers" },
  { href: "/lookup", label: "Vehicle lookup" },
];

export function NavBar({ user }: { user: StaffUser }) {
  const pathname = usePathname();
  const router = useRouter();

  async function signOut() {
    await fetch("/api/auth/logout", { method: "POST" });
    router.replace("/login");
    router.refresh();
  }

  return (
    <header className="border-b border-slate-200 bg-white">
      <div className="mx-auto flex max-w-6xl items-center gap-6 px-4 py-3">
        <Link href="/bookings" className="text-sm font-semibold text-brand">
          ShirazTyres
        </Link>

        <nav className="flex flex-1 gap-1">
          {LINKS.map((link) => {
            const active = pathname.startsWith(link.href);
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`rounded-md px-3 py-1.5 text-sm transition ${
                  active ? "bg-slate-100 font-medium text-ink" : "text-ink-muted hover:bg-slate-50"
                }`}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>

        <span className="hidden text-xs text-ink-muted sm:block">
          {user.name} · {user.role}
        </span>
        <button onClick={signOut} className="text-xs text-ink-muted underline hover:text-ink">
          Sign out
        </button>
      </div>
    </header>
  );
}
