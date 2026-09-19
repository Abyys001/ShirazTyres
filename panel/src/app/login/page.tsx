"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";

import { BrandMark } from "@/components/brand";
import { Button, Field, Input } from "@/components/ui";

/**
 * Seeded by `make seed`. Shown only in a development build, so the owner and
 * office accounts do not have to be looked up in the seed command each time.
 */
const DEV_ACCOUNTS = [
  { email: "owner@shiraztyres.co.uk", password: "shiraz1234", role: "Owner — full access" },
];
const DEV_MODE = process.env.NODE_ENV === "development";

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  /**
   * Takes the credentials rather than reading the state: the development
   * buttons below sign in with an account the fields have not been set to yet,
   * and a setState is not visible until the next render.
   */
  async function signIn(withEmail: string, withPassword: string) {
    setPending(true);
    setError(null);

    const response = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: withEmail, password: withPassword }),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      setError(body?.errors?.detail?.[0] ?? body?.detail ?? "Could not sign in.");
      setPending(false);
      return;
    }

    router.replace(params.get("next") || "/jobs");
    router.refresh();
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    void signIn(email, password);
  }

  return (
    <div className="w-full max-w-sm space-y-4">
      <form onSubmit={submit} className="space-y-6 rounded-2xl border border-line bg-surface p-7">
        <div className="space-y-4">
          <BrandMark className="h-12" />
          <div>
            <h1 className="font-display text-2xl font-bold tracking-tight">
              <span className="text-ink">Shiraz</span>
              <span className="text-brand">Tyres</span>
            </h1>
            <p className="mt-0.5 text-sm text-ink-muted">Dispatch, drivers and invoicing.</p>
          </div>
        </div>

        <Field label="Email">
          <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus />
        </Field>
        <Field label="Password" error={error}>
          <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </Field>

        <Button type="submit" disabled={pending} className="w-full py-2.5">
          {pending ? "Signing in…" : "Sign in"}
        </Button>
      </form>

      {DEV_MODE ? (
        <div className="rounded-2xl border border-line bg-surface-sunken p-4">
          <p className="text-sm font-medium text-ink">Development sign-in</p>
          <p className="mt-0.5 text-xs text-ink-subtle">
            Seeded by <span className="tabular">make seed</span>. Pick one to sign in.
          </p>
          <ul className="mt-3 space-y-1">
            {DEV_ACCOUNTS.map((account) => (
              <li key={account.email}>
                <button
                  type="button"
                  disabled={pending}
                  onClick={() => {
                    // Fill the fields as well, so a failed sign-in leaves
                    // something to correct rather than two empty boxes.
                    setEmail(account.email);
                    setPassword(account.password);
                    void signIn(account.email, account.password);
                  }}
                  className="w-full rounded-md px-2 py-1.5 text-left transition hover:bg-surface-raised disabled:opacity-50"
                >
                  <span className="block text-sm tabular text-ink">{account.email}</span>
                  <span className="block text-xs text-ink-subtle">
                    {account.role}, password {account.password}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-10">
      <Suspense>
        <LoginForm />
      </Suspense>
    </main>
  );
}
