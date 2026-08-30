import Link from "next/link";

import { SiteHeader } from "@/components/site-header";
import { getTokens } from "@/lib/session";

export default async function HomePage() {
  const { refresh } = await getTokens();
  const signedIn = Boolean(refresh);

  return (
    <>
      <SiteHeader signedIn={signedIn} />
      <main className="mx-auto max-w-3xl space-y-8 px-4 py-12">
        <section className="space-y-4">
          <h1 className="text-3xl font-semibold">Flat tyre in London? We come to you.</h1>
          <p className="text-lg text-ink-muted">
            Tell us your registration and where you are. The nearest ShirazTyres technician is sent to you
            with the right tyre on board.
          </p>
          <Link href={signedIn ? "/request" : "/sign-in?next=/request"}>
            <span className="inline-flex rounded-lg bg-brand px-5 py-3 font-medium text-brand-fg hover:bg-brand-dark">
              Request a technician
            </span>
          </Link>
        </section>

        <section className="grid gap-4 sm:grid-cols-3">
          <Step number={1} title="Your registration">
            We look up your vehicle and the tyre size the manufacturer specifies.
          </Step>
          <Step number={2} title="Your location">
            We use your device position, so the technician finds you and not your postcode.
          </Step>
          <Step number={3} title="Track your job">
            You see who is coming, what they are driving, and how long they will be.
          </Step>
        </section>
      </main>
    </>
  );
}

function Step({ number, title, children }: { number: number; title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-line bg-surface p-5">
      <p className="text-xs font-semibold text-brand">Step {number}</p>
      <h2 className="mt-1 font-medium">{title}</h2>
      <p className="mt-1 text-sm text-ink-muted">{children}</p>
    </div>
  );
}
