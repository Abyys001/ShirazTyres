# A Next.js surface, built for production.
#
# This used to be `npm run dev` with the source bind-mounted — which is a
# development server, and shipped one: every route compiled on first visit, and
# the browser was handed about nine megabytes of unminified JavaScript per page
# load. Over a local network that is merely wasteful. Over the internet it means
# the server-rendered HTML — which is every list in its "Loading…" state — sits
# on screen for as long as the download takes, and the panel looks like it has
# lost the API rather than like it is still arriving. The same build as a
# production bundle is about 120 kB.
#
# `output: "standalone"` in next.config.mjs is what makes the last stage
# possible: Next traces the server's actual dependencies and emits a server.js
# beside them, so the runtime image carries neither the toolchain nor the full
# node_modules.

# ----------------------------------------------------------------- deps ----
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# ---------------------------------------------------------------- build ----
FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# NEXT_PUBLIC_* values are inlined into the browser bundle by `next build`, so
# they have to be here rather than in the runtime environment — a production
# build cannot read them later. The same is true of anything the middleware
# reads, because the edge runtime inlines its environment too. Changing one of
# these means rebuilding the image, which is the honest cost of having them
# compiled in.
ARG NEXT_PUBLIC_API_BASE_URL
ARG NEXT_PUBLIC_WS_BASE_URL
ARG NEXT_PUBLIC_MAP_TILE_URL
ARG NEXT_PUBLIC_MAP_TILE_ATTRIBUTION
ARG NEXT_PUBLIC_WEBSITE_URL
ARG NEXT_PUBLIC_GOOGLE_CLIENT_ID
ARG NEXT_PUBLIC_DEV_TOOLS
ARG COOKIE_SECURE

ENV NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL \
    NEXT_PUBLIC_WS_BASE_URL=$NEXT_PUBLIC_WS_BASE_URL \
    NEXT_PUBLIC_MAP_TILE_URL=$NEXT_PUBLIC_MAP_TILE_URL \
    NEXT_PUBLIC_MAP_TILE_ATTRIBUTION=$NEXT_PUBLIC_MAP_TILE_ATTRIBUTION \
    NEXT_PUBLIC_WEBSITE_URL=$NEXT_PUBLIC_WEBSITE_URL \
    NEXT_PUBLIC_GOOGLE_CLIENT_ID=$NEXT_PUBLIC_GOOGLE_CLIENT_ID \
    NEXT_PUBLIC_DEV_TOOLS=$NEXT_PUBLIC_DEV_TOOLS \
    COOKIE_SECURE=$COOKIE_SECURE \
    NEXT_TELEMETRY_DISABLED=1

# Not every surface has static files of its own — the website has none — and
# the runtime stage below copies this unconditionally.
RUN mkdir -p public && npm run build

# -------------------------------------------------------------- runtime ----
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# The three pieces a standalone build is made of. `static` and `public` are not
# traced into it — Next expects them to be placed beside server.js by hand.
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public

EXPOSE 3000
CMD ["node", "server.js"]
