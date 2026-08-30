# ShirazTyres — customer website

Next.js 15 (App Router) + React 19 + TanStack Query + Tailwind + Leaflet.

Server-rendered and deliberately light: it is opened by someone standing next to
a broken-down car, on whatever signal they have.

## The flow

1. **Sign in** — Google or phone OTP, both reaching the same account (4.1).
2. **Registration** — the lookup returns the vehicle and its tyre size (4.2).
3. **Tyre confirmation** — confirm, or decline and take responsibility. Path B
   shows the notice, requires an acknowledgement, and only then opens the fields;
   both figures go with the request (4.3).
4. **Location** — browser geolocation, with a map pin for anyone who declines the
   permission. There is no postcode box, on purpose. Coverage is checked the
   moment a position arrives, so somebody outside the area finds out before
   filling in anything else (4.4).
5. **Issue and submit** (4.5).
6. **Track** — status, the technician's first name, photograph and van, and a
   live ETA over a WebSocket (4.6).

The tracking page has no map. The ETA is recalculated on the backend each time
the technician's van moves and only the figure is sent.

## Tokens never reach the browser

Sign-in posts to `/api/auth/otp-verify` or `/api/auth/google`, which store both
JWTs in httpOnly cookies. Every client-side call goes through
`/api/proxy/[...path]`. The WebSocket gets a short-lived access token from
`/api/auth/ws-token`, because a handshake cannot carry a header.

## Hand-off from the marketing site

`web-widget/` sends visitors here with `?plate=…&lat=…&lng=…`, and `/request`
picks those up, so nothing is typed twice.

## Run it

```bash
cd website
npm install
npm run dev        # http://localhost:3000 (3001 under docker compose)
```

Environment: `NEXT_PUBLIC_API_BASE_URL`, `NEXT_PUBLIC_WS_BASE_URL`,
`API_BASE_URL` (server-side), `NEXT_PUBLIC_MAP_TILE_URL`,
`NEXT_PUBLIC_GOOGLE_CLIENT_ID`.

Without a Google client id the sign-in page falls back to the API's development
mock, so the two-routes-one-account flow can still be exercised end to end.
