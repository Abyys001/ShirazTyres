"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

import { Button, Field, Input, Notice } from "@/components/ui";

const CLIENT_ID = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID ?? "";

interface GoogleIdentity {
  accounts: {
    id: {
      initialize: (config: { client_id: string; callback: (response: { credential: string }) => void }) => void;
      renderButton: (parent: HTMLElement, options: Record<string, unknown>) => void;
    };
  };
}

declare global {
  interface Window {
    google?: GoogleIdentity;
  }
}

/**
 * Google sign-in (specification 4.1).
 *
 * With no client id configured — local development — this falls back to the API's mock
 * token form so the two-routes-one-account flow can still be exercised end to end.
 */
export function GoogleButton({ next }: { next: string }) {
  const router = useRouter();
  const target = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<string | null>(null);
  const [mockEmail, setMockEmail] = useState("");

  async function signIn(idToken: string) {
    const response = await fetch("/api/auth/google", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id_token: idToken }),
    });
    const body = await response.json();
    if (!response.ok) {
      setError(body.detail ?? "Google sign-in failed.");
      return;
    }
    router.replace(next);
    router.refresh();
  }

  useEffect(() => {
    if (!CLIENT_ID || !target.current) return;

    const script = document.createElement("script");
    script.src = "https://accounts.google.com/gsi/client";
    script.async = true;
    script.onload = () => {
      if (!window.google || !target.current) return;
      window.google.accounts.id.initialize({
        client_id: CLIENT_ID,
        callback: (response) => void signIn(response.credential),
      });
      window.google.accounts.id.renderButton(target.current, {
        theme: "outline",
        size: "large",
        width: 320,
        text: "continue_with",
      });
    };
    document.head.appendChild(script);

    return () => {
      script.remove();
    };
    // signIn closes over router only, which is stable for the life of the page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!CLIENT_ID) {
    return (
      <div className="space-y-2">
        <Notice tone="warning">
          Google sign-in is not configured. In development you can sign in with any email address.
        </Notice>
        <Field label="Email address">
          <Input
            value={mockEmail}
            onChange={(event) => setMockEmail(event.target.value)}
            placeholder="you@example.com"
            type="email"
          />
        </Field>
        <Button
          variant="secondary"
          className="w-full"
          disabled={!mockEmail}
          onClick={() => void signIn(`mock:${mockEmail}`)}
        >
          Continue with Google (development)
        </Button>
        {error ? <Notice tone="error">{error}</Notice> : null}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div ref={target} />
      {error ? <Notice tone="error">{error}</Notice> : null}
    </div>
  );
}
