#!/bin/bash
# Build both Flutter apps for the web and drop them into the panel's static
# files, so the office can open either app in a browser tab from the panel
# itself — no emulator, no handset, no second server.
#
#   make web-apps          # or: scripts/build_web_apps.sh
#
# The panel serves `panel/public/` at its own origin, so the builds land at
# /apps/driver/ and /apps/customer/ and need no CORS entry of their own beyond
# the panel origin the API already trusts.
#
# This is a development and demo aid. A browser has no push notifications, no
# background location and no camera on a desktop — the web build is for driving
# the flow, not for shipping to a technician.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/panel/public/apps"

# ~/.zshrc pins PUB_HOSTED_URL at a mirror that is unreachable from here, and a
# Flutter command inheriting it fails with a bare "Failed to update packages".
export PUB_HOSTED_URL="${PUB_HOSTED_URL_OVERRIDE:-https://pub.dev}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL_OVERRIDE:-https://storage.googleapis.com}"

# These are baked into the build, so they have to be the address the *browser*
# will use — not the compose-internal one, and not localhost unless the stack is
# only ever opened on the machine it runs on.
#
# NEXT_PUBLIC_API_BASE_URL and NEXT_PUBLIC_WS_BASE_URL in .env already hold
# exactly that, because the panel and the website hand them to their own
# browsers. Following them means a stack published on a server builds apps that
# reach that server, rather than apps that reach whoever opens them.
if [ -f "$ROOT/.env" ]; then
  BACKEND_HOST_PORT="$(sed -n 's/^BACKEND_HOST_PORT=//p' "$ROOT/.env" | tail -1)"
  ENV_API_BASE_URL="$(sed -n 's/^NEXT_PUBLIC_API_BASE_URL=//p' "$ROOT/.env" | tail -1)"
  ENV_WS_BASE_URL="$(sed -n 's/^NEXT_PUBLIC_WS_BASE_URL=//p' "$ROOT/.env" | tail -1)"
  ENV_MAP_TILE_URL="$(sed -n 's/^MAP_TILE_URL=//p' "$ROOT/.env" | tail -1)"
  ENV_MAP_ATTRIBUTION="$(sed -n 's/^MAP_TILE_ATTRIBUTION=//p' "$ROOT/.env" | tail -1)"
fi
BACKEND_HOST_PORT="${BACKEND_HOST_PORT:-8000}"
API_BASE_URL="${API_BASE_URL:-${ENV_API_BASE_URL:-http://localhost:$BACKEND_HOST_PORT/api/v1}}"
WS_BASE_URL="${WS_BASE_URL:-${ENV_WS_BASE_URL:-ws://localhost:$BACKEND_HOST_PORT/ws}}"

# `flutter build web` is a release build, so `kDebugMode` is false and the
# development sign-in panel — the seeded numbers and the mock OTP — would be
# hidden. It is the whole point of the browser build, so it is asked for
# explicitly. DEV_SIGN_IN=false turns it off for a demo.
DEV_SIGN_IN="${DEV_SIGN_IN:-true}"

# The basemap. `AppConfig.mapTileUrl` falls back to OpenStreetMap only in a
# debug build — a release one draws its own graticule rather than quietly taking
# tiles nobody paid for. `flutter build web` is a release build, so a web app
# built without this had no map at all: the picker and the live ETA screen came
# up as a bare grid of coordinates. It is the same MAP_TILE_URL the panel and
# the website are handed by docker-compose, so all four surfaces agree.
MAP_TILE_URL="${MAP_TILE_URL:-${ENV_MAP_TILE_URL:-}}"
MAP_ATTRIBUTION="${MAP_ATTRIBUTION:-${ENV_MAP_ATTRIBUTION:-© OpenStreetMap contributors}}"

if [ -z "$MAP_TILE_URL" ]; then
  echo "note: MAP_TILE_URL is empty — both apps will draw a graticule, not a map." >&2
fi

build() {
  local dir="$1" slug="$2" label="$3"
  echo "==> $label → panel/public/apps/$slug"
  rm -rf "${OUT:?}/$slug"
  (
    cd "$ROOT/$dir"

    # Resolve from the cache first, and reach for the network only when it does
    # not have what the pubspec asks for. pub.dev answers 403 from here often
    # enough — it fetches a security advisory per package, and that is the call
    # that gets refused — to sink a build whose dependencies have not changed
    # since the last one. `--no-pub` below keeps the build itself from
    # resolving a second time and undoing this.
    flutter pub get --offline >/dev/null 2>&1 || flutter pub get

    flutter build web \
      --no-pub \
      --release \
      --base-href "/apps/$slug/" \
      --dart-define=API_BASE_URL="$API_BASE_URL" \
      --dart-define=WS_BASE_URL="$WS_BASE_URL" \
      --dart-define=DEV_SIGN_IN="$DEV_SIGN_IN" \
      --dart-define=MAP_TILE_URL="$MAP_TILE_URL" \
      --dart-define=MAP_ATTRIBUTION="$MAP_ATTRIBUTION"
  )
  mkdir -p "$OUT"
  cp -r "$ROOT/$dir/build/web" "$OUT/$slug"
}

build mobile          driver   "Technician app"
build mobile_customer customer "Customer app"

echo
echo "Built against $API_BASE_URL"
echo "Basemap: ${MAP_TILE_URL:-none (graticule only)}"
echo "Open them from the panel's Apps page."
