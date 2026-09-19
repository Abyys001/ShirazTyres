import fs from "node:fs";
import path from "node:path";

import { notFound } from "next/navigation";

import { Card } from "@/components/ui";

/**
 * Every surface of the product, openable in a browser tab from the panel.
 *
 * The two Flutter apps are the reason this page exists. Testing a change to
 * either of them used to mean an emulator or a handset, which is a five-minute
 * detour when the question is "does the offer land?" — so they are built for the
 * web (`make web-apps`) into this panel's own static files and opened from here.
 *
 * The web build is a development and demo aid, not a shipping target: a browser
 * tab has no push notifications, no background location, and on a desktop no
 * usable camera. What it does have is the whole flow, live against the same API.
 */
type Surface = {
  slug: string;
  name: string;
  who: string;
  blurb: string;
  credential: string;
  /**
   * Built into `public/`, so the button is only honest if the files are there.
   *
   * The link goes to `index.html` rather than the directory: Next.js serves
   * `public/` file by file and does not resolve a directory to its index, so the
   * bare path is normalised to `/apps/<slug>` and lands on this page's 404. The
   * build's own `--base-href` makes every asset inside resolve correctly anyway.
   */
  built?: string;
  href: string;
  missing?: string;
};

const SURFACES: Surface[] = [
  {
    slug: "driver",
    name: "Technician app",
    who: "ShirazTyres technicians",
    blurb:
      "Go on shift, take an offer, drive the job through to an invoice on the customer's drive.",
    credential: "07700900301 — 07700900304 approved, 07700900305 pending",
    built: "driver",
    href: "/apps/driver/index.html",
    missing: "make web-apps",
  },
  {
    slug: "customer",
    name: "Customer app",
    who: "the stranded motorist",
    blurb: "Report a puncture, confirm the tyre size, and follow the van in on a live ETA.",
    credential: "07700900101 — 07700900103, or any number to register",
    built: "customer",
    href: "/apps/customer/index.html",
    missing: "make web-apps",
  },
  {
    slug: "website",
    name: "Customer website",
    who: "customers on the web",
    blurb: "The same call-out, raised from a desktop browser instead of the app.",
    credential: "the same customer numbers",
    href: "https://shiraztyres.co.uk/",
  },
];

/**
 * `public/apps/<slug>/index.html` rather than the directory: an interrupted
 * build leaves the directory behind, and a button into an empty one is worse
 * than no button.
 */
function isBuilt(slug: string): boolean {
  return fs.existsSync(path.join(process.cwd(), "public", "apps", slug, "index.html"));
}

export default function AppsPage() {
  // The rail hides the link in a production bundle; the route has to refuse as
  // well, or a deployed panel still serves a page of localhost links to anybody
  // who types the path.
  if (process.env.NODE_ENV === "production") notFound();

  return (
    <div className="space-y-4">
      <p className="max-w-3xl text-sm text-ink-muted">
        Each surface of the product, in a browser tab. The two apps are Flutter web builds of
        the real thing running against this same API — good enough to drive a whole call-out,
        but without push, background location or a camera.
      </p>

      <div className="grid gap-4 sm:grid-cols-2">
        {SURFACES.map((surface) => {
          const ready = surface.built === undefined || isBuilt(surface.built);
          return (
            <Card key={surface.slug} title={surface.name}>
              <div className="flex h-full flex-col gap-3">
                <div className="space-y-1.5">
                  <p className="text-xs uppercase tracking-wider text-ink-subtle">{surface.who}</p>
                  <p className="text-sm text-ink-muted">{surface.blurb}</p>
                </div>

                <dl className="text-xs text-ink-subtle">
                  <dt className="sr-only">Sign in with</dt>
                  <dd>{surface.credential}</dd>
                </dl>

                <div className="mt-auto pt-1">
                  {ready ? (
                    <a
                      href={surface.href}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center justify-center gap-2 rounded-md bg-brand px-3 py-2 text-sm font-medium text-brand-fg transition hover:bg-brand-dark"
                    >
                      Open {surface.name.toLowerCase()}
                      <IconExternal />
                    </a>
                  ) : (
                    <p className="text-xs text-ink-subtle">
                      Not built yet — run{" "}
                      <code className="rounded bg-surface-raised px-1 py-0.5 text-ink-muted">
                        {surface.missing}
                      </code>
                    </p>
                  )}
                </div>
              </div>
            </Card>
          );
        })}
      </div>
    </div>
  );
}

function IconExternal() {
  return (
    <svg
      aria-hidden
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-3.5 w-3.5"
    >
      <path d="M14 4h6v6M20 4l-8.5 8.5" />
      <path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" />
    </svg>
  );
}
