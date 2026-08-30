# ShirazTyres — owner panel

Next.js 15 (App Router) + React 19 + TanStack Query + Tailwind + Leaflet.

## What it does

| Page | Covers |
|---|---|
| `/jobs` | the live queue, filters, stats, an unclaimed-job alert, manual entry |
| `/jobs/[id]` | detail, the tyre-confirmation record, dispatch control and trail, the invoice, history |
| `/map` | the live technician map, fed by WebSocket |
| `/drivers` | onboarding queue, the document-expiry watchlist |
| `/drivers/[id]` | verification, document review, service areas, tracking |
| `/invoices` | everything billed, and marking payment |
| `/lookup` | the standalone plate lookup, independent of any job |
| `/settings` | the whole configuration catalogue, plus the price list and service areas |

## Tokens never reach the browser

Sign-in posts to `/api/auth/login`, which stores both JWTs in httpOnly cookies.
Every client-side call goes through `/api/proxy/[...path]`, which attaches the
access token server-side and refreshes it once on a 401.

The one exception is the WebSocket: a browser cannot set a header on a handshake,
so `/api/auth/ws-token` hands the page the short-lived access token for that one
use. The refresh token — the one worth stealing — never leaves the cookie jar.

## Settings render themselves

`GET /settings` returns values **and** the specs describing them: type, label,
help text, choices, default. The settings screen renders from those, so a new
setting added to the backend catalogue appears in the panel with no front-end
change.

## Run it

```bash
cd panel
npm install
npm run dev        # http://localhost:3000
```

`npm run generate:types` regenerates `src/types/openapi.d.ts` from
`backend/openapi.yaml`. `src/types/api.ts` is the hand-maintained subset the UI
actually consumes.

Environment: `NEXT_PUBLIC_API_BASE_URL`, `NEXT_PUBLIC_WS_BASE_URL`,
`API_BASE_URL` (server-side, inside the compose network),
`NEXT_PUBLIC_MAP_TILE_URL`.

## Maps

The map needs a tile URL. With none configured it still works — markers on a
plain background — rather than quietly borrowing tiles from OSM's own server,
which their usage policy does not permit for a commercial service. See
`docs/deployment.md`.
