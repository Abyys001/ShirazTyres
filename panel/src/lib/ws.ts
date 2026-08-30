"use client";

import { useEffect, useRef, useState } from "react";

const WS_BASE_URL = (process.env.NEXT_PUBLIC_WS_BASE_URL ?? "ws://localhost:8000/ws").replace(/\/$/, "");

export interface PanelEvent {
  event: string;
  [key: string]: unknown;
}

/**
 * The panel's live feed: job changes and driver positions (specification 11.1).
 *
 * A browser cannot set an Authorization header on a WebSocket handshake, so the token
 * goes in the query string. It is fetched from the Next server on demand rather than
 * stored in client state, and it is the same short-lived access token the API takes.
 */
export function usePanelFeed(onEvent: (event: PanelEvent) => void) {
  const [connected, setConnected] = useState(false);
  const handler = useRef(onEvent);
  handler.current = onEvent;

  useEffect(() => {
    let socket: WebSocket | null = null;
    let retry: ReturnType<typeof setTimeout> | null = null;
    let closed = false;
    let attempt = 0;

    async function connect() {
      if (closed) return;
      let token: string;
      try {
        const response = await fetch("/api/auth/ws-token");
        if (!response.ok) throw new Error("no token");
        token = ((await response.json()) as { token: string }).token;
      } catch {
        retry = setTimeout(connect, 5000);
        return;
      }

      socket = new WebSocket(`${WS_BASE_URL}/panel?token=${encodeURIComponent(token)}`);

      socket.onopen = () => {
        attempt = 0;
        setConnected(true);
      };
      socket.onmessage = (message) => {
        try {
          handler.current(JSON.parse(message.data) as PanelEvent);
        } catch {
          // A frame we cannot parse is not worth tearing the socket down for.
        }
      };
      socket.onclose = () => {
        setConnected(false);
        if (closed) return;
        attempt += 1;
        retry = setTimeout(connect, Math.min(30_000, 1000 * 2 ** attempt));
      };
    }

    void connect();

    return () => {
      closed = true;
      if (retry) clearTimeout(retry);
      socket?.close();
    };
  }, []);

  return connected;
}
