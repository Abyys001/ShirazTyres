"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";

import type { StaffUser } from "@/types/api";

const LINKS = [
  { href: "/jobs", label: "Jobs" },
  { href: "/map", label: "Live map" },
  { href: "/drivers", label: "Drivers" },
  { href: "/invoices", label: "Invoices" },
  { href: "/lookup", label: "Vehicle lookup" },
  { href: "/settings", label: "Settings" },
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
    <header className="border-b border-line bg-surface">
      <div className="mx-auto flex max-w-7xl items-center gap-6 px-4 py-3">
        <Link href="/jobs" className="font-display text-sm font-bold tracking-tight text-brand">
          ShirazTyres
        </Link>

        <nav className="flex flex-1 flex-wrap gap-1">
          {LINKS.map((link) => {
            const active = pathname.startsWith(link.href);
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`rounded-md px-3 py-1.5 text-sm transition ${
                  active
                    ? "bg-brand/10 font-medium text-brand"
                    : "text-ink-muted hover:bg-surface-raised hover:text-ink"
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
