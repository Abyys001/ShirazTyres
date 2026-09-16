# Design tokens

The palette is taken from the brand swatch files (`adobe swatch.aco`,
`figma-colors.json`, `sketch palette.sketchpalette`). Two colours carry the
identity — **gold `#FFD700`** on the **near-black `#0B1315`** — over a cool
slate neutral ramp. Dark is the shipped theme across every surface.

## Source palette

| Role | Hex |
| --- | --- |
| Brand gold | `#FFD700` |
| Brand gold, pressed | `#FBBF24` |
| Brand gold, warning tint | `#FACC15` |
| Canvas (the void) | `#0B1315` |
| Neutrals | slate `#F8FAFC` → `#020617` |
| Accent (teal-blue) | `#0078A8` |
| Info | `#3B82F6` · `#2563EB` · `#1E40AF` |
| Success | `#4ADE80` · `#22C55E` |
| Danger | `#DC2626` · `#FECACA` |
| WhatsApp | `#25D366` |

## Web (`website/`, `panel/`)

Tokens live as RGB triplets on `:root` / `.dark` in `src/app/globals.css` and
are exposed through `tailwind.config.ts`, so `/opacity` modifiers work
(`bg-brand/10`).

| Token | Tailwind class |
| --- | --- |
| `--st-canvas` | `bg-canvas` |
| `--st-surface`, `-raised`, `-sunken` | `bg-surface`, `bg-surface-raised`, `bg-surface-sunken` |
| `--st-line`, `-strong` | `border-line`, `border-line-strong` |
| `--st-ink`, `-muted`, `-subtle`, `-inverse` | `text-ink`, `text-ink-muted`, `text-ink-subtle`, `text-ink-inverse` |
| `--st-brand` | `bg-brand` / `text-brand`; hover `bg-brand-dark`; tint `bg-brand-light`; label on gold `text-brand-fg` |
| `--st-accent` / `-success` / `-warning` / `-danger` / `-info` | `text-accent`, `bg-success`, … |

Never reach for a raw Tailwind palette colour (`slate-700`, `amber-100`) in a
component — it will not follow a theme flip. Use a token, or the `gold-*` ramp
if a token really is too coarse.

Status badges go through the `.chip-*` component classes (`chip-warn`,
`chip-info`, `chip-accent`, `chip-brand`, `chip-ok`, `chip-danger`,
`chip-muted`), so a tone change lands in every badge map at once.

The light token set is complete. Flipping either app is dropping `dark` from
`<html className="dark …">` in `src/app/layout.tsx`.

## Fonts

| Slot | Family | Used for |
| --- | --- | --- |
| `font-display` | `ui-sans-serif` | headings, wordmark |
| `font-sans` | `ui-sans-serif` | everything else |
| `font-mono` | JetBrains Mono 500/700 | registrations, prices, job references |

Headings and body are set in the reader's own UI face — Roboto on Android, SF on
iOS, whatever the desktop is set to in the panel. It is already on the device, so
it costs nothing to load and cannot arrive late. Flutter spells it as a **null**
`fontFamily` (see `Fonts` in `lib/core/theme.dart`); the web spells it
`ui-sans-serif` at the head of the stack in `tailwind.config.ts`. With one face
doing both jobs, weight, size and tracking are what separate a heading from a
paragraph.

Mono is the exception and is still **vendored, not fetched**: registrations and
money have to line up in a column, and that is not something the platform face
can be relied on for. Each surface carries its own copy, so a build needs no
egress to `fonts.googleapis.com`.

| Surface | Files | Wired up in |
| --- | --- | --- |
| `panel/` | `src/fonts/JetBrainsMono-Variable.woff2` | `next/font/local` in `src/app/layout.tsx` |
| `website/` | `src/fonts/*-Variable.woff2` (still Sora + Inter) | `next/font/local` in `src/app/layout.tsx` |
| `mobile/`, `mobile_customer/` | `assets/fonts/JetBrainsMono-<weight>.ttf` | the `fonts:` block in `pubspec.yaml` |

The web keeps its faces variable (one file per family, `weight: "400 700"`);
Flutter gets static instances per declared weight, because a static face is what
its weight matching is reliable against. The OFL licence ships alongside each
set.

Regenerating them — after a font update, or to add a weight — is
`scripts/build_fonts.py`, which pulls the upstream `Family[wght].ttf`, pins the
axes with `fontTools.varLib.instancer`, subsets with `fontTools.subset`, and
drops each family into the projects that declare it. Its output is committed, so
a normal build never runs it.

## Logo

`LOGO.png` at the repo root is the master. Two derivatives ship: the original
navy-and-gold for light surfaces, and a variant with the blue family remapped up
the lightness scale for dark ones — navy on the technician app's ink canvas is a
hole. The gold is identity and does not move.

| Surface | Files | Wired up in |
| --- | --- | --- |
| `panel/` | `src/brand/logo.png`, `logo-dark.png` | `BrandMark` in `src/components/brand.tsx` |
| `mobile/`, `mobile_customer/` | `assets/brand/{,2.0x/,3.0x/}logo{,-dark}.png` | `BrandLogo` in `lib/widgets/brand_logo.dart` |

Neither caller picks a variant: `BrandMark` renders both and lets `dark:` hide
one, and `BrandLogo` reads the palette's brightness. The drawn `ShirazMark`
survives only as the spinner — it is the one thing artwork cannot do.

## Flutter (`mobile/`, `mobile_customer/`)

`lib/core/theme.dart` is identical in both apps, and so is `lib/widgets/ui_kit.dart`.

| Layer | What it holds |
| --- | --- |
| `Brand` | the colour constants, mirroring the web tokens |
| `Space` | the 4pt scale (`xs` 4 → `xxxl` 48) every screen lays out on |
| `Radii` | `control` 14, `card` 20, `pill` — two shapes, no third |
| `Fonts` | the family names the vendored faces register under |
| `Motion` | `fast` 140ms, `normal` 240ms, `slow` 400ms — every animation |
| type scale | nothing is set below 12.5pt. These screens are read one-handed, outdoors, in weather: a caption nobody can read should not have been written. |
| `buildTheme()` | one `ThemeData` wiring all of the above into Material 3 |

`statusColour()` feeds the status chip, which draws the colour at 12% as a
background, 28% as a border and full strength on the dot and label.

The screens are assembled from `ui_kit.dart` rather than raw `Card`/`Padding`:
`SurfaceCard` (optionally accented down its border, or washed in the gold
gradient), `SectionHeader` (a tracked eyebrow, optionally numbered for a step in
a flow), `PlateBadge`, `StatBlock`, `DetailRow`, `InlineNotice`, `BusyButton`,
`AppEmptyState` and `LoadingBlock`. The mark itself lives in
`widgets/brand_logo.dart` (`ShirazMark`, `SpinningMark`, `BrandBadge`) and the
sign-in flows in `widgets/auth_kit.dart`. Reaching for a raw number
instead of a token is what makes two screens drift apart, so there should be no
reason to.

### Interaction

Both apps are used one-handed, outdoors, often in gloves, sometimes at 2am. The
kit is built round that rather than round a desk.

| Component | Where it is used, and why |
| --- | --- |
| `AppNavBar` / `NavItem` | the top-level destinations, always labelled, each a full thumb-width target. Nothing lives behind an icon in a corner. |
| `ChoiceTile` / `ChoiceGrid` | picking one of a few things — the issue type, the tyre confirmation, the payment method. An icon over a word or two on a 104pt target, two to a row. Replaces every drop-down and radio list. |
| `ChoiceRow` | the same job where the option needs a sentence and a tile would wrap. |
| `SlideAction` | anything that cannot be undone: advancing a job's status, taking payment. A 60% drag does not happen by accident in a jacket pocket; a tap does. |
| `StickyBar` | holds the primary action above the gesture bar, so it is under the thumb wherever the page is scrolled to. |
| `StepBar` | progress through a numbered flow, as filled segments rather than a sentence. |
| `ProgressRail` | the stages of a job as a horizontal rail. Answers "where are we up to" from the shape, before any of it is read. |
| `HeroFigure` | the one number a screen exists to show — an ETA, a total — at display size with its unit on the baseline. |
| `QuickAction` | a round icon over its label: call, navigate, correct the size. |
| `ExpandableCard` | detail worth keeping but not worth reading every time. Collapsed by default. |
| `Skeleton` | a sweeping placeholder shaped like what replaces it, so the layout never jumps. |
| `Buzz` | haptics named by meaning — `tap` for a control, `commit` for something irreversible, `alert` for an offer arriving. Every committing control goes through one. |

Copy follows the same rule as the targets: the screen says the shortest true
thing. Anything longer — the tyre-size liability terms, what being on shift
costs in privacy — lives one tap away in a sheet or on the account screen, not
in a paragraph between the question and the button.

Development sign-in helpers live in `lib/widgets/dev_sign_in.dart` and are gated
on `AppConfig.devSignInEnabled` — see `docs/dev-logins.md`.

## Embeddable widget (`web-widget/`)

`src/shiraztyres-widget.js` declares its own tokens on `:host` inside the shadow
root, so the host page cannot bleed in and the widget costs the host no font
request. `<shiraztyres-widget theme="light">` switches it to the light set for
hosts with a light layout.

## The mark

An S cut through a tyre: eighteen tread blocks around the rim and one continuous
groove through the middle. One symbol, one colour, a plain ground — which is
what survives being 48 pixels wide on a home screen, and the tread reads as a
solid ring the moment it is too small to count.

It is drawn twice from the same geometry, and the two must be kept in step:

- `lib/widgets/brand_logo.dart` paints it live, so the badge in the app and the
  loading spinner are the same object as the launcher tile. `spin` turns the
  tread without moving the groove — the wheel is running, the letter is not.
- `tools/make-icons.py` renders it to every Android and iOS launcher size, the
  adaptive foreground and monochrome layers, and the launch images.

The two apps are exact negatives of each other, which is the whole point: the
motorist's app is ink on gold, the technician's gold on ink, and nobody with
both installed taps the wrong one. `BrandBadge(inverted: true)` is the dark
treatment inside the app.

Run `python3 tools/make-icons.py` from the repository root after changing the
geometry, and change `brand_logo.dart` to match.
