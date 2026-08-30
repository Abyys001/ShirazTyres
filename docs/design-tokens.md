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
| `font-display` | Sora 600/700 | headings, wordmark |
| `font-sans` | Inter | everything else |
| `font-mono` | JetBrains Mono 500/700 | registrations, prices, job references |

Loaded with `next/font/google` in each app's `layout.tsx`, which means **the
build needs egress to `fonts.googleapis.com`**. Next caches them under
`.next/cache`; a fully air-gapped build would need the files vendored into
`public/` and `next/font/local` instead.

## Flutter (`mobile/`, `mobile_customer/`)

`lib/core/theme.dart` is identical in both apps. Colours are constants on the
`Brand` class, mirroring the web tokens; `statusColour()` feeds the status chip,
which draws the colour at 12% as a background and full strength as the label.
No webfont is bundled — the platform sans is used, with the type scale carrying
the brand voice instead.

## Embeddable widget (`web-widget/`)

`src/shiraztyres-widget.js` declares its own tokens on `:host` inside the shadow
root, so the host page cannot bleed in and the widget costs the host no font
request. `<shiraztyres-widget theme="light">` switches it to the light set for
hosts with a light layout.
