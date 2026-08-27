# ShirazTyres website widget

A single dependency-free script that adds the emergency call-out flow to the
existing website. No build step, no framework, and it renders inside a shadow
root so the host page's CSS and the widget's CSS cannot collide.

## Embed

```html
<div id="shiraztyres-callout"
     data-api="https://api.shiraztyres.co.uk/api/v1"
     data-phone="+441234567890"></div>
<script src="/shiraztyres-widget.js" defer></script>
```

`data-api` defaults to `/api/v1` if omitted (same-origin deployments).
`data-phone` is optional and only adds a "prefer to talk?" line.

Multiple instances work: any element with `data-shiraztyres-callout` is
upgraded too.

## Flow

1. `GET /vehicle-lookup/{plate}` — optional, fills in make/model and tyre size.
2. `POST /auth/otp/request` with `purpose: "booking"` — texts a code.
3. `POST /public/bookings` with the payload plus `code` — creates the call-out
   and notifies the shop.

No account and no token are involved; the phone number is proved by the OTP.

## Events

On success the host element emits a bubbling `shiraztyres:booked` event whose
`detail` is the created booking, so the site can fire its own analytics:

```js
document.addEventListener('shiraztyres:booked', (event) => {
  gtag('event', 'callout_booked', { reference: event.detail.reference });
});
```

## Local demo

```bash
cd web-widget && python3 serve.py
```

then open <http://localhost:5500/demo.html> with the backend running on
`localhost:8000` and `SMS_PROVIDER=mock` (the code box is pre-filled).

`serve.py` proxies `/api/*` to the backend so the demo runs same-origin, which
is how the widget is deployed on the real site.

## CORS

Same-origin (the widget served from the same host as the API, or behind the
same reverse proxy) needs no CORS at all — prefer it. If `data-api` points at
another origin, add the website's origin to `CORS_ALLOWED_ORIGINS` in the
backend `.env`.
