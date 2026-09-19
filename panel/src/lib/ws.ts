"use client";

import { useEffect, useRef, useState } from "react";

const WS_BASE_URL = (process.env.NEXT_PUBLIC_WS_BASE_URL ?? "ws://localhost:8000/ws").replace(/\/$/, "");

/** Idle WebSockets get closed by proxies long before anything interesting happens. */
const PING_INTERVAL_MS = 25_000;

/**
 * Where to try for the socket, in order.
 *
 * Every REST call the panel makes goes through `/api/proxy` — same origin,
 * whatever address the browser happened to open the panel on. The socket had no
 * such luxury: its host is compiled into the bundle from
 * `NEXT_PUBLIC_WS_BASE_URL`, so opening the panel on any other address — an SSH
 * tunnel to localhost, a second interface, a domain put in front of it — left a
 * board whose data loaded perfectly and whose live feed could never connect. It
 * said "Reconnecting" forever and nobody could see why, because everything else
 * worked.
 *
 * So the configured address is a first choice, not the only one. If it will not
 * connect, the same port and path are tried on whatever host the panel itself
 * was served from, under a scheme that matches the page — which is the right
 * answer in every deployment where the API and the panel sit on one machine,
 * and this one does. Whichever answers is kept for the rest of the session.
 */
function candidateUrls(): string[] {
  const urls = [WS_BASE_URL];
  if (typeof window === "undefined") return urls;

  try {
    const configured = new URL(WS_BASE_URL);
    const secure = window.location.protocol === "https:";
    const sameHost = new URL(configured.toString());
    sameHost.protocol = secure ? "wss:" : "ws:";
    sameHost.hostname = window.location.hostname;
    urls.push(sameHost.toString().replace(/\/$/, ""));
  } catch {
    // An unparseable NEXT_PUBLIC_WS_BASE_URL is worth no extra candidates.
  }

  return [...new Set(urls)];
}

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
  private opening = false;

  /** Candidates, and where we are in them. Pinned to one once it connects. */
  private urls: string[] | null = null;
  private cursor = 0;

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
    // `opening` as well as `socket`: this is async from the first line, and two
    // subscribers mounting in the same tick used to get two handshakes, one of
    // which was then orphaned with nothing left holding a reference to close it.
    if (this.listeners.size === 0 || this.socket || this.opening) return;
    this.opening = true;

    try {
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

      this.urls ??= candidateUrls();
      const base = this.urls[this.cursor % this.urls.length];

      let socket: WebSocket;
      try {
        socket = new WebSocket(`${base}/panel?token=${encodeURIComponent(token)}`);
      } catch {
        // The constructor throws rather than returning — a `ws://` URL on an
        // `https:` page is refused as mixed content before a packet moves. This
        // used to escape an async method nobody awaited, so the retry below was
        // never scheduled and the badge stayed on "Reconnecting" for good.
        this.cursor += 1;
        this.scheduleRetry();
        return;
      }

      this.socket = socket;
      this.attach(socket, base);
    } finally {
      this.opening = false;
    }
  }

  private attach(socket: WebSocket, base: string) {
    socket.onopen = () => {
      this.attempt = 0;
      // This address works; stop offering the others the next time round.
      this.urls = [base];
      this.cursor = 0;
      this.setConnected(true);
      this.ping = setInterval(() => {
        if (socket.readyState === WebSocket.OPEN) socket.send("ping");
      }, PING_INTERVAL_MS);
    };

    // A socket that errors always closes too, so the recovery lives in one
    // place. This is here to stop the error reaching the console as unhandled.
    socket.onerror = () => {};

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
      const wasConnected = this.connected;
      this.setConnected(false);
      // Closed without ever opening: this address is the wrong one, or the
      // token was refused. Move to the next candidate before backing off, so a
      // panel opened on a second address finds the socket within a second
      // rather than never.
      if (!wasConnected) this.cursor += 1;
      this.scheduleRetry();
    };
  }

  private scheduleRetry() {
    if (this.listeners.size === 0 || this.retry) return;
    this.attempt += 1;

    // Walking the candidate list is not a failure to back off from — only a
    // full lap of it without a connection is.
    const laps = Math.floor(this.attempt / Math.max(1, this.urls?.length ?? 1));
    const delay = laps === 0 ? 400 : Math.min(30_000, 1000 * 2 ** laps);

    this.retry = setTimeout(() => {
      this.retry = null;
      void this.open();
    }, delay);
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
