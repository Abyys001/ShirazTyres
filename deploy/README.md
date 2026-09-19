# Deploying behind nginx

The compose stack publishes the panel on `3100`, the API on `8100` and the
customer site on `3101`. Those are the right thing on a workbench and the wrong
thing on the open internet, for a reason that is not obvious until it happens:

A non-standard port over plain http is among the first things an intermediary
throttles or drops, **and it fails in the worst possible way**. The HTML is a
few kilobytes and arrives; the JavaScript is not and does not. What is left on
screen is the server-rendered markup — which is every list in its `Loading…`
state — so the panel reads as one that has lost its API. Nothing appears in any
log, because the browser never ran the code that makes the requests.

`nginx/shiraztyres.conf` puts the panel and the API on **one origin on 443**.
That fixes the above and two other things with it: there is no CORS between the
panel and the API any more, and the WebSocket is same-origin rather than a
second port that has to be reachable on its own.

## Installing it

```bash
sudo cp deploy/nginx/shiraztyres.conf /etc/nginx/sites-available/shiraztyres
sudo ln -sfn /etc/nginx/sites-available/shiraztyres /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

If this machine serves other sites, check them before and after. The vhost
matches `server_name` only, so named vhosts are untouched — with one exception,
noted in the file: it claims `default_server` on 443, because a browser opening
`https://<an IP>` sends no SNI and nginx has no name to select a certificate by.

## The certificate

**Let's Encrypt will not issue for a bare IP address.** It refuses at the
client, before any network call:

```
Requested name 159.195.199.91 is an IP address.
The Let's Encrypt certificate authority will not issue certificates for a bare IP address.
```

So the certificate in use is self-signed, generated with the IP in
`subjectAltName` (which is what a browser actually checks):

```bash
sudo mkdir -p /etc/ssl/shiraztyres && cd /etc/ssl/shiraztyres
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout ip.key -out ip.crt \
  -subj "/CN=159.195.199.91/O=ShirazTyres" \
  -addext "subjectAltName=IP:159.195.199.91" \
  -addext "basicConstraints=CA:FALSE" \
  -addext "keyUsage=digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"
sudo chmod 600 ip.key
```

It encrypts the traffic. It cannot authenticate it, so every browser shows a
warning on first visit that somebody has to click through, and anyone able to
sit in the path could present their own certificate and nobody would know.
**This is a stopgap, not a destination.**

### Replacing it with a real one

Point a hostname at this machine — an `A` record for, say,
`shiraz.example.co.uk` — and then:

```bash
sudo certbot certonly --webroot -w /var/www/acme -d shiraz.example.co.uk
```

Then in `deploy/nginx/shiraztyres.conf`:

- put the hostname in both `server_name` lines,
- swap the two `ssl_certificate*` paths for the ones certbot reports,
- drop `default_server` from the `listen 443` lines — a named vhost is selected
  by SNI and does not need it,
- and now that the certificate is a real one, add HSTS:
  `add_header Strict-Transport-Security "max-age=31536000" always;`

Finally, in `.env`, replace `159.195.199.91` with the hostname in
`NEXT_PUBLIC_API_BASE_URL`, `NEXT_PUBLIC_WS_BASE_URL`, `PANEL_BASE_URL`,
`CORS_ALLOWED_ORIGINS` and `CSRF_TRUSTED_ORIGINS`, set `COOKIE_SECURE=true`,
then rebuild — these are compiled into the browser bundle, so a restart is not
enough:

```bash
docker compose up -d --build panel website
scripts/build_web_apps.sh      # the Flutter web builds bake the API URL in too
```

## Hardening still to do

The raw ports (`3100`, `3101`, `8100`) are still published, deliberately: they
are a way back in if nginx is misconfigured, and anything already pointed at
`:8100` keeps working. They are also a way around the proxy, so once the
hostname and the real certificate are in place, bind them to loopback in
`docker-compose.yml` —

```yaml
ports:
  - "127.0.0.1:${PANEL_HOST_PORT:-3000}:3000"
```

— and set `COOKIE_SECURE=true` at the same time. The two go together: marking
the session cookies `Secure` while the same panel is also reachable over plain
http on `:3100` produces a panel that loads on that port and silently refuses to
log anybody in.
