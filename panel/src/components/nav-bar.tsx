"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { type ReactNode, useEffect, useRef, useState } from "react";

import { BrandLockup } from "@/components/brand";
import { LiveBadge } from "@/components/live-sync";
import { ChangePasswordForm } from "@/components/staff-manager";
import { api } from "@/lib/client-api";
import type { JobStats, StaffUser } from "@/types/api";

type NavLink = { href: string; label: string; icon: ReactNode };

/*
 * Grouped, because a flat list of six makes "Vehicle lookup" and "Jobs" look like
 * the same kind of thing. They are not: one is the shift, the other is a reference
 * you reach for twice a day. The headings cost a line each and make the rail
 * scannable by intent rather than by reading every label.
 */
const GROUPS: { heading: string; links: NavLink[] }[] = [
  {
    heading: "Operations",
    links: [
      { href: "/jobs", label: "Jobs", icon: <IconJobs /> },
      { href: "/map", label: "Live map", icon: <IconMap /> },
      { href: "/drivers", label: "Drivers", icon: <IconDrivers /> },
      { href: "/customers", label: "Customers", icon: <IconCustomers /> },
    ],
  },
  {
    heading: "Money",
    links: [{ href: "/invoices", label: "Invoices", icon: <IconInvoices /> }],
  },
  {
    heading: "Reference",
    links: [{ href: "/lookup", label: "Vehicle lookup", icon: <IconLookup /> }],
  },
  {
    heading: "System",
    links: [{ href: "/settings", label: "Settings", icon: <IconSettings /> }],
  },
];

const LINKS = GROUPS.flatMap((group) => group.links);

/**
 * A rail rather than a row of links across the top.
 *
 * The panel lives on a wallboard for a whole shift, where the vertical edge is
 * dead space and the full width belongs to the board. Putting navigation down
 * the side also gives the unclaimed count a permanent home in the corner of the
 * eye — on the old top nav it existed only while somebody had the jobs page open,
 * which is the one place it was not needed.
 */
export function NavBar({ user }: { user: StaffUser }) {
  const pathname = usePathname();

  // Shares the jobs page's cache entry, so LiveSync keeps the rail current too.
  const stats = useQuery({
    queryKey: ["job-stats"],
    queryFn: () => api<JobStats>("/jobs/stats"),
    refetchInterval: 60_000,
  });
  const unclaimed = stats.data?.unclaimed ?? 0;
  const live = stats.data?.open_total ?? 0;
  const onShift = stats.data?.drivers_online ?? 0;

  return (
    <aside className="border-b border-line bg-surface lg:sticky lg:top-0 lg:flex lg:h-screen lg:flex-col lg:border-b-0 lg:border-r">
      <div className="flex items-center gap-3 px-4 py-3.5 lg:px-5">
        <Link href="/jobs" aria-label="ShirazTyres — jobs">
          <BrandLockup markClassName="h-9" wordClassName="text-base" />
        </Link>
      </div>

      {/*
       * The two figures that decide whether the shift is under control: cars
       * waiting on us, and vans available to go. They sit above navigation
       * because they are the reason somebody walked over to the screen.
       */}
      <div className="hidden gap-2 px-4 pb-4 lg:grid lg:grid-cols-2">
        <CountCircle
          value={live}
          label="Live jobs"
          href="/jobs"
          tone={unclaimed > 0 ? "alarm" : "brand"}
          title={
            unclaimed > 0
              ? `${live} live, ${unclaimed} with nobody coming`
              : `${live} live right now`
          }
        />
        <CountCircle
          value={onShift}
          label="On shift"
          href="/map"
          tone={onShift > 0 ? "ok" : "idle"}
          pulse={onShift > 0}
          title={`${onShift} driver${onShift === 1 ? "" : "s"} on shift`}
        />
      </div>

      <nav className="flex gap-1 overflow-x-auto px-3 pb-3 lg:flex-1 lg:flex-col lg:gap-0 lg:overflow-y-auto lg:overflow-x-visible">
        {GROUPS.map((group) => (
          <div key={group.heading} className="contents lg:mb-3 lg:block">
            <p className="hidden px-3 pb-1 text-xs font-medium uppercase tracking-wider text-ink-subtle lg:block">
              {group.heading}
            </p>
            {group.links.map((link) => {
              const active = pathname.startsWith(link.href);
              const alarm = link.href === "/jobs" && unclaimed > 0;
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  aria-current={active ? "page" : undefined}
                  className={`group relative flex shrink-0 items-center gap-2.5 rounded-md px-3 py-2 text-sm transition lg:shrink ${
                    active
                      ? "bg-brand/10 font-medium text-brand"
                      : "text-ink-muted hover:bg-surface-raised hover:text-ink"
                  }`}
                >
                  {/* The active marker is a bar on the rail's own edge, not a fill. */}
                  <span
                    aria-hidden
                    className={`absolute inset-y-1.5 -left-3 w-0.5 rounded-r bg-brand transition-opacity ${
                      active ? "opacity-100" : "opacity-0"
                    } hidden lg:block`}
                  />
                  <span className="shrink-0 opacity-80">{link.icon}</span>
                  <span className="flex-1">{link.label}</span>
                  {alarm ? (
                    <span
                      className="rounded-full bg-danger px-1.5 py-0.5 text-xs font-semibold leading-none text-ink-inverse tabular-nums"
                      title={`${unclaimed} waiting for a driver`}
                    >
                      {unclaimed}
                    </span>
                  ) : null}
                </Link>
              );
            })}
          </div>
        ))}
      </nav>

      <div className="hidden border-t border-line px-5 py-3.5 lg:block">
        <p className="truncate text-sm font-medium text-ink">{user.name}</p>
        <p className="text-xs capitalize text-ink-subtle">{roleLabel(user.role)}</p>
      </div>
    </aside>
  );
}

/**
 * A count drawn as a ring rather than a number in a box.
 *
 * The ring is the affordance: it reads as a gauge from across the room, where a
 * bare figure reads as a label. When jobs are unclaimed the jobs ring takes the
 * alarm tone and the slow halo from `globals.css`, which is the only moving
 * thing in the rail and so the only thing that can interrupt.
 */
function CountCircle({
  value,
  label,
  href,
  tone,
  title,
  pulse = false,
}: {
  value: number;
  label: string;
  href: string;
  tone: "brand" | "alarm" | "ok" | "idle";
  title: string;
  pulse?: boolean;
}) {
  const tones = {
    brand: "border-brand/45 text-brand",
    alarm: "border-danger/60 text-danger alarm-ring",
    ok: "border-success/50 text-success",
    idle: "border-line-strong text-ink-subtle",
  }[tone];

  return (
    <Link
      href={href}
      title={title}
      className="flex flex-col items-center gap-1.5 rounded-md py-1 transition hover:bg-surface-raised"
    >
      <span
        className={`flex h-14 w-14 items-center justify-center rounded-full border-2 bg-surface font-display text-xl font-bold tabular-nums ${tones}`}
      >
        {value}
      </span>
      <span className="flex items-center gap-1 text-xs leading-none text-ink-muted">
        {pulse ? (
          <span aria-hidden className="live-dot h-1.5 w-1.5 rounded-full bg-success" />
        ) : null}
        {label}
      </span>
    </Link>
  );
}

/** The page's own header: what you are looking at, and whether it is still live. */
export function TopBar({ user }: { user: StaffUser }) {
  const pathname = usePathname();
  const title = LINKS.find((link) => pathname.startsWith(link.href))?.label ?? "Jobs";

  return (
    <header className="sticky top-0 z-20 flex items-center gap-3 border-b border-line bg-canvas/85 px-4 py-3 backdrop-blur lg:px-6">
      <h1 className="flex-1 font-display text-lg font-semibold tracking-tight">{title}</h1>
      <LiveBadge />
      <AccountMenu user={user} />
    </header>
  );
}

/**
 * Signing out is destructive — a half-written job on screen goes with it — so it
 * is not a bare word in the corner that a sleeve can catch. The trigger states
 * who is signed in, which is the question actually being asked when somebody
 * looks up here, and the sign-out sits behind the menu as its own deliberate act.
 */
function AccountMenu({ user }: { user: StaffUser }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [changing, setChanging] = useState(false);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: MouseEvent) {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  async function signOut() {
    setBusy(true);
    try {
      await fetch("/api/auth/logout", { method: "POST" });
      router.replace("/login");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div ref={root} className="relative">
      <button
        onClick={() => setOpen((value) => !value)}
        aria-haspopup="menu"
        aria-expanded={open}
        className={`flex items-center gap-2 rounded-md border px-2 py-1.5 text-sm transition ${
          open
            ? "border-line-strong bg-surface-raised text-ink"
            : "border-transparent text-ink-muted hover:bg-surface-raised hover:text-ink"
        }`}
      >
        <Avatar name={user.name} />
        <span className="hidden max-w-[10rem] truncate font-medium sm:block">{user.name}</span>
        <IconChevron className={`transition-transform ${open ? "rotate-180" : ""}`} />
      </button>

      {open ? (
        <div
          role="menu"
          className="absolute right-0 top-full z-30 mt-1.5 max-h-[80vh] w-72 overflow-y-auto rounded-lg border border-line bg-surface shadow-md"
        >
          <div className="flex items-center gap-3 border-b border-line px-3 py-3">
            <Avatar name={user.name} size="lg" />
            <div className="min-w-0">
              <p className="truncate text-sm font-medium text-ink">{user.name}</p>
              <p className="truncate text-xs text-ink-subtle">{user.email}</p>
              <p className="mt-1 text-xs font-medium text-brand">{roleLabel(user.role)}</p>
            </div>
          </div>

          {changing ? (
            <div className="border-b border-line p-3">
              <ChangePasswordForm onDone={() => setChanging(false)} />
            </div>
          ) : null}

          <div className="p-1.5">
            {changing ? null : (
              <button
                role="menuitem"
                onClick={() => setChanging(true)}
                className="flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-sm text-ink-muted transition hover:bg-surface-raised hover:text-ink"
              >
                <IconKey />
                Change password
              </button>
            )}
            <button
              role="menuitem"
              onClick={signOut}
              disabled={busy}
              className="flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-sm text-danger transition hover:bg-danger/10 disabled:opacity-50"
            >
              <IconSignOut />
              {busy ? "Signing out…" : "Sign out"}
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function Avatar({ name, size = "sm" }: { name: string; size?: "sm" | "lg" }) {
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
  const sizing = size === "lg" ? "h-9 w-9 text-sm" : "h-6 w-6 text-xs";
  return (
    <span
      aria-hidden
      className={`flex shrink-0 items-center justify-center rounded-full bg-brand/15 font-semibold text-brand ${sizing}`}
    >
      {initials || "?"}
    </span>
  );
}

function roleLabel(role: StaffUser["role"]): string {
  if (role === "owner") return "Owner";
  if (role === "shop_owner") return "Shop owner";
  return "Office";
}

/* Inline rather than a dependency: six glyphs do not justify an icon package. */

function IconJobs() {
  return (
    <Svg>
      <path d="M3 7h18M3 12h18M3 17h10" />
    </Svg>
  );
}

function IconMap() {
  return (
    <Svg>
      <path d="m9 4-6 3v13l6-3 6 3 6-3V4l-6 3z" />
      <path d="M9 4v13M15 7v13" />
    </Svg>
  );
}

function IconDrivers() {
  return (
    <Svg>
      <path d="M16 20v-1a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v1" />
      <circle cx="9" cy="7" r="3.2" />
      <path d="M18 8.5h2.2L22 11v3h-3" />
    </Svg>
  );
}

function IconInvoices() {
  return (
    <Svg>
      <path d="M6 2h9l4 4v16l-2.5-1.5L14 22l-2-1.5L10 22l-2.5-1.5L5 22V5a3 3 0 0 1 1-3z" />
      <path d="M9 9h6M9 13h6" />
    </Svg>
  );
}

function IconCustomers() {
  return (
    <Svg>
      <circle cx="12" cy="8" r="3.5" />
      <path d="M5.5 20a6.5 6.5 0 0 1 13 0" />
    </Svg>
  );
}

function IconLookup() {
  return (
    <Svg>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.6-3.6" />
    </Svg>
  );
}

function IconSettings() {
  return (
    <Svg>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9 17 7M7 17l-2.1 2.1" />
    </Svg>
  );
}

function IconSignOut() {
  return (
    <Svg className="h-4 w-4">
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <path d="m16 17 5-5-5-5M21 12H9" />
    </Svg>
  );
}

function IconKey() {
  return (
    <Svg className="h-4 w-4">
      <circle cx="8" cy="15" r="4" />
      <path d="m10.8 12.2 8-8 2.2 2.2-2 2 2 2-3 3-2-2-1.4 1.4" />
    </Svg>
  );
}

function IconChevron({ className = "" }: { className?: string }) {
  return (
    <Svg className={`h-3.5 w-3.5 ${className}`}>
      <path d="m6 9 6 6 6-6" />
    </Svg>
  );
}

function Svg({ children, className = "h-4 w-4" }: { children: ReactNode; className?: string }) {
  return (
    <svg
      aria-hidden
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
    >
      {children}
    </svg>
  );
}
