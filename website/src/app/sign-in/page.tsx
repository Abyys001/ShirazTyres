"use client";

import { useMutation } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";

import { GoogleButton } from "@/components/google-button";
import { SiteHeader } from "@/components/site-header";
import { Button, Card, Field, Input, Notice } from "@/components/ui";

interface OtpRequestResult {
  expires_at: string;
  resend_after_seconds: number;
  debug_code?: string;
}

/**
 * Two sign-in routes, one account (specification 4.1). A customer who starts with
 * Google and later uses OTP on the same number lands on the same job history — the
 * joining is done on the server, on the verified email.
 */
function SignIn() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next") ?? "/request";

  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState<OtpRequestResult | null>(null);

  const requestCode = useMutation({
    mutationFn: async () => {
      const response = await fetch("/api/auth/otp-request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.detail ?? "Could not send a code.");
      return body as OtpRequestResult;
    },
    onSuccess: setSent,
  });

  const verify = useMutation({
    mutationFn: async () => {
      const response = await fetch("/api/auth/otp-verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone, code }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.detail ?? "That code was not accepted.");
      return body;
    },
    onSuccess: () => {
      router.replace(next);
      router.refresh();
    },
  });

  return (
    <>
      <SiteHeader signedIn={false} />
      <main className="mx-auto max-w-md space-y-4 px-4 py-10">
        <Card title="Sign in">
          <div className="space-y-4">
            <GoogleButton next={next} />

            <div className="flex items-center gap-3 text-xs text-ink-subtle">
              <span className="h-px flex-1 bg-surface-sunken" />
              or use your phone
              <span className="h-px flex-1 bg-surface-sunken" />
            </div>

            <Field label="Mobile number">
              <Input
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                placeholder="07700 900123"
                inputMode="tel"
                autoComplete="tel"
              />
            </Field>

            {sent ? (
              <>
                <Field label="Code we texted you">
                  <Input
                    value={code}
                    onChange={(event) => setCode(event.target.value)}
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    className="font-mono tracking-[0.4em]"
                  />
                </Field>
                {sent.debug_code ? (
                  <Notice tone="warning">
                    Development mode — your code is <strong>{sent.debug_code}</strong>.
                  </Notice>
                ) : null}
                <Button className="w-full" onClick={() => verify.mutate()} disabled={verify.isPending}>
                  {verify.isPending ? "Checking…" : "Sign in"}
                </Button>
                <button
                  className="w-full text-xs text-ink-muted underline"
                  onClick={() => requestCode.mutate()}
                  disabled={requestCode.isPending}
                >
                  Send another code
                </button>
              </>
            ) : (
              <Button
                className="w-full"
                onClick={() => requestCode.mutate()}
                disabled={!phone || requestCode.isPending}
              >
                {requestCode.isPending ? "Sending…" : "Text me a code"}
              </Button>
            )}

            {requestCode.isError ? <Notice tone="error">{requestCode.error.message}</Notice> : null}
            {verify.isError ? <Notice tone="error">{verify.error.message}</Notice> : null}
          </div>
        </Card>
      </main>
    </>
  );
}

export default function SignInPage() {
  return (
    <Suspense>
      <SignIn />
    </Suspense>
  );
}
