"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

export function SiteHeader({ signedIn }: { signedIn: boolean }) {
  const router = useRouter();

  async function signOut() {
    await fetch("/api/auth/logout", { method: "POST" });
    router.replace("/");
    router.refresh();
  }

  return (
    <header className="border-b border-line bg-surface">
      <div className="mx-auto flex max-w-3xl items-center gap-4 px-4 py-3">
        <Link href="/" className="font-display text-base font-bold tracking-tight text-brand">
          ShirazTyres
        </Link>
        <nav className="flex flex-1 justify-end gap-3 text-sm">
          {signedIn ? (
            <>
              <Link href="/request" className="text-ink-muted hover:text-ink">
                New call-out
              </Link>
              <Link href="/jobs" className="text-ink-muted hover:text-ink">
                My call-outs
              </Link>
              <Link href="/garage" className="text-ink-muted hover:text-ink">
                My vehicles
              </Link>
              <button onClick={signOut} className="text-ink-muted underline hover:text-ink">
                Sign out
              </button>
            </>
          ) : (
            <Link href="/sign-in" className="text-ink-muted hover:text-ink">
              Sign in
            </Link>
          )}
        </nav>
      </div>
    </header>
  );
}
