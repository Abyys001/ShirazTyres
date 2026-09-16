"use client";

import { useEffect, useRef, useState } from "react";

const WS_BASE_URL = (process.env.NEXT_PUBLIC_WS_BASE_URL ?? "ws://localhost:8000/ws").replace(/\/$/, "");

/** Idle WebSockets get closed by proxies long before anything interesting happens. */
const PING_INTERVAL_MS = 25_000;

export interface PanelEvent {
  event: string;
  [key: string]: unknown;
}

type Listener = (event: PanelEvent) => void;

/**
 * One socket for the whole panel, shared by every hook that asks for it.
 *
 * The panel used to open a connection per page that wanted one, which meant the
 * map, the job list and the job page each held their own — three handshakes,
 * three reconnect timers, and three chances for one of them to be the stale one.
 * There is exactly one now; the last listener to leave closes it.
 */
class PanelFeed {
  private socket: WebSocket | null = null;
  private listeners = new Set<Listener>();
  private statusListeners = new Set<(connected: boolean) => void>();
  private retry: ReturnType<typeof setTimeout> | null = null;
  private ping: ReturnType<typeof setInterval> | null = null;
  private attempt = 0;
  private connected = false;

  get isConnected() {
    return this.connected;
  }

  subscribe(listener: Listener) {
    this.listeners.add(listener);
    if (this.listeners.size === 1) void this.open();
    return () => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0) this.close();
    };
  }

  watchStatus(listener: (connected: boolean) => void) {
    this.statusListeners.add(listener);
    return () => {
      this.statusListeners.delete(listener);
    };
  }

  private setConnected(value: boolean) {
    if (this.connected === value) return;
    this.connected = value;
    this.statusListeners.forEach((listener) => listener(value));
  }

  private async open() {
    if (this.listeners.size === 0 || this.socket) return;

    let token: string;
    try {
      const response = await fetch("/api/auth/ws-token");
      if (!response.ok) throw new Error("no token");
      token = ((await response.json()) as { token: string }).token;
    } catch {
      this.scheduleRetry();
      return;
    }
    // Everyone may have gone away while the token was in flight.
    if (this.listeners.size === 0) return;

    const socket = new WebSocket(`${WS_BASE_URL}/panel?token=${encodeURIComponent(token)}`);
    this.socket = socket;

    socket.onopen = () => {
      this.attempt = 0;
      this.setConnected(true);
      this.ping = setInterval(() => {
        if (socket.readyState === WebSocket.OPEN) socket.send("ping");
      }, PING_INTERVAL_MS);
    };

    socket.onmessage = (message) => {
      let parsed: PanelEvent;
      try {
        parsed = JSON.parse(message.data as string) as PanelEvent;
      } catch {
        return; // A frame we cannot parse is not worth tearing the socket down for.
      }
      if (parsed.event === "pong") return;
      this.listeners.forEach((listener) => listener(parsed));
    };

    socket.onclose = () => {
      if (this.socket !== socket) return;
      this.socket = null;
      this.stopPing();
      this.setConnected(false);
      this.scheduleRetry();
    };
  }

  private scheduleRetry() {
    if (this.listeners.size === 0 || this.retry) return;
    this.attempt += 1;
    this.retry = setTimeout(() => {
      this.retry = null;
      void this.open();
    }, Math.min(30_000, 1000 * 2 ** this.attempt));
  }

  private stopPing() {
    if (this.ping) clearInterval(this.ping);
    this.ping = null;
  }

  private close() {
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    this.stopPing();
    const socket = this.socket;
    this.socket = null;
    this.setConnected(false);
    socket?.close();
  }
}

const feed = new PanelFeed();

/**
 * The panel's live feed: job changes, dispatch rounds, driver positions, invoices.
 *
 * A browser cannot set an Authorization header on a WebSocket handshake, so the token
 * goes in the query string. It is fetched from the Next server on demand rather than
 * stored in client state, and it is the same short-lived access token the API takes.
 */
export function usePanelFeed(onEvent: (event: PanelEvent) => void) {
  const [connected, setConnected] = useState(feed.isConnected);
  const handler = useRef(onEvent);
  handler.current = onEvent;

  useEffect(() => {
    const stopEvents = feed.subscribe((event) => handler.current(event));
    const stopStatus = feed.watchStatus(setConnected);
    setConnected(feed.isConnected);
    return () => {
      stopEvents();
      stopStatus();
    };
  }, []);

  return connected;
}

/**
 * Just "is the panel live?", for pages that let `LiveSync` do the invalidating and
 * only need to know how hard to poll as a fallback.
 */
export function useLiveStatus() {
  const [connected, setConnected] = useState(feed.isConnected);

  useEffect(() => {
    const stop = feed.watchStatus(setConnected);
    setConnected(feed.isConnected);
    return stop;
  }, []);

  return connected;
}
