# ShirazTyres website widget

A single dependency-free script that adds an emergency call-out entry point to
the existing marketing site. No build step, no framework, and it renders inside
a shadow root so the host page's CSS and the widget's CSS cannot collide.

## What it does, and what it deliberately does not

Version 1.0 of this widget created a call-out on its own. Version 2.0 does not,
and cannot: specification 4.1 gives every customer an account, and 4.3 requires
an explicit tyre-specification decision before a request may be submitted.
Neither belongs in an anonymous embed on a marketing page.

So the widget answers the three questions a stranded motorist has in the first
ten seconds — *will you come to me, what is my tyre size, what will it cost* —
and then hands over to the customer site with the plate and position already in
the URL, so nothing is typed twice.

| Step | Endpoint |
|---|---|
| Fee, VAT and opening hours | `GET /public/config` |
| Are we in the service area? | `POST /public/coverage` |
| The vehicle and its tyre size | `GET /public/vehicle-lookup/{plate}` |

All three are anonymous by design. Nothing else is called.

## Embed

```html
<div id="shiraztyres-callout"
     data-api="https://api.shiraztyres.co.uk/api/v1"
     data-site="https://request.shiraztyres.co.uk/request"
     data-phone="+441234567890"></div>
<script src="/shiraztyres-widget.js" defer></script>
```

- `data-api` defaults to `/api/v1` (same-origin deployments).
- `data-site` is the customer website's request page; defaults to `/request`.
- `data-phone` is optional and only adds a "prefer to talk?" line.

Multiple instances work: any element with `data-shiraztyres-callout` is
upgraded too.

## Hand-off

The widget navigates to `data-site` with `plate`, `lat` and `lng` in the query
string, and first emits a bubbling `shiraztyres:handoff` event so the host site
can fire its own analytics:

```js
document.addEventListener('shiraztyres:handoff', (event) => {
  gtag('event', 'callout_started', { destination: event.detail.url });
});
```

## Local demo

```bash
cd web-widget && python3 serve.py
```

then open <http://localhost:5500/demo.html> with the backend running on
`localhost:8000`. `serve.py` proxies `/api/*` to the backend so the demo runs
same-origin, which is how the widget is deployed on the real site.

## CORS

Same-origin (the widget served from the same host as the API, or behind the same
reverse proxy) needs no CORS at all — prefer it. If `data-api` points at another
origin, add the website's origin to `CORS_ALLOWED_ORIGINS` in the backend `.env`.
