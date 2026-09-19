# Development sign-in

Every surface signs in with a real credential — there is no bypass. In
development the credentials are seeded and the SMS provider is mocked, so the
verification code comes back in the API response instead of a text message.

```bash
cp .env.example .env          # SMS_PROVIDER=mock, GOOGLE_OAUTH_MOCK=1
make up
make migrate
make seed                     # creates everything below
```

## Owner panel — <http://localhost:3000>

| Email | Password | Role |
| --- | --- | --- |
| `owner@shiraztyres.co.uk` | `shiraz1234` | Owner, full access |

`office@shiraztyres.co.uk` is seeded as a staff user with no usable password;
set one with `manage.py changepassword` if you need a second role to test with.

The login page lists this account in a **Development sign-in** panel and fills
the form when you click it. It renders only when `NODE_ENV=development`.

## Driver app (`mobile/`)

Phone plus OTP. No passwords.

| Number | Name | State |
| --- | --- | --- |
| `07700900301` | Amir Hosseini | Approved, online |
| `07700900302` | Grace Okafor | Approved, online |
| `07700900303` | Tomasz Nowak | Approved, online |
| `07700900304` | Priya Raman | Approved, online |
| `07700900305` | Daniel Cole | Pending review — lands on onboarding |

Any number not in the list registers a new driver in `pending`, which is the
path to walk when testing Section 8.1.

An unapproved driver is refused by every dispatch endpoint, so the app asks for
none of them: the shift screen is the standing, and it says whose move it is —
*Finish setting up* while something is outstanding, *Waiting for approval* once
it is all in. Approve `07700900305` from **Drivers → Awaiting approval** in the
panel and the offers and the board appear on their phone without it being
reopened, because the decision goes out on the driver's own channel.

**The list is no longer compiled into the app.** Both sign-in screens read it
from `GET /api/v1/auth/dev/accounts`, which answers from the database — so a
driver created in the owner panel appears here the moment they exist, and a
number that was removed from the seed stops being offered. The endpoint is
served only when `DEBUG=1` *and* the request is not over HTTPS, and it returns
names and numbers only: no codes, no tokens, and nothing the ordinary OTP flow
does not already give you.

A driver created from the panel is approved on the spot when nothing is
outstanding, and left `pending` when `drivers.required_documents` still wants
paperwork (Section 8.2). Either way they can sign in immediately — a pending
driver simply lands on onboarding and is offered no jobs.

## Customer app (`mobile_customer/`)

| Number | Name | State |
| --- | --- | --- |
| `07700900101` | Sara Ahmadi | Vehicle and job history |
| `07700900102` | James Whitfield | Vehicle and job history |
| `07700900103` | Nadia Rahimi | Vehicle and job history |

Any other number registers a new customer on first code.

**Google sign-in** needs no OAuth credentials while `GOOGLE_OAUTH_MOCK=1`: the
API accepts `mock:<email>` in place of an ID token. The same endpoint returns the
token to use, so the button disappears by itself when the mock is switched off.
It resolves to the seeded Sara Ahmadi account — the same account her phone number
reaches, which is Section 4.1 working.

## Where the code comes from

With `SMS_PROVIDER=mock`, `POST /api/v1/auth/otp/request` returns the code as
`debug_code`. Both apps read it, prefill the code field, and show it in a gold
banner on the development panel. Nothing to copy out of a log.

By hand:

```bash
curl -s -X POST localhost:8000/api/v1/auth/otp/request \
  -H 'Content-Type: application/json' \
  -d '{"phone":"07700900301","purpose":"driver"}'
# {"expires_at":"…","resend_after_seconds":60,"debug_code":"123456"}
```

`purpose` is `driver` for the driver app and `login` for the customer app and
website — a code issued for one will not verify the other.

## Turning the helpers off

The development panel appears when the build is a debug build **and** the API
base URL is plain `http://`. A release build, or a debug build pointed at a real
API, never shows it. To force it either way:

```bash
flutter run --dart-define=DEV_SIGN_IN=false
```

## If a sign-in fails

- **"Cannot reach ShirazTyres"** — the API is not up, or the app is pointed at
  the wrong host. An Android emulator reaches this machine on `10.0.2.2`, an iOS
  simulator on `localhost`; the app resolves that per platform. On a physical
  device run `adb reverse tcp:8000 tcp:8000`, or pass
  `--dart-define=API_BASE_URL=http://<your-lan-ip>:8000/api/v1` and add that
  address to `android/app/src/main/res/xml/network_security_config.xml`.
- **"Please wait Ns before requesting another code"** — `OTP_RESEND_COOLDOWN_SECONDS`,
  10 by default. The apps disable the resend button for exactly that long.
- **"No verification code was requested for this number"** — the code was issued
  under the other `purpose`, or a newer request retired it.
