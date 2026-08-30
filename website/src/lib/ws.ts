"use client";

import { useEffect, useRef, useState } from "react";

const WS_BASE_URL = (process.env.NEXT_PUBLIC_WS_BASE_URL ?? "ws://localhost:8000/ws").replace(/\/$/, "");

export interface CustomerEvent {
  event: string;
  [key: string]: unknown;
}

/**
 * The customer's live feed (specification 4.6): status changes and a recalculated ETA.
 * The driver's position is never on this channel — the server does not send it here.
 */
export function useCustomerFeed(onEvent: (event: CustomerEvent) => void) {
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

      socket = new WebSocket(`${WS_BASE_URL}/customer?token=${encodeURIComponent(token)}`);
      socket.onopen = () => {
        attempt = 0;
        setConnected(true);
      };
      socket.onmessage = (message) => {
        try {
          handler.current(JSON.parse(message.data) as CustomerEvent);
        } catch {
          // Ignore a frame we cannot parse rather than dropping the connection.
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
