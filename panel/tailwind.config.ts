import type { Config } from "tailwindcss";

/** Tokens resolve through CSS variables (see globals.css) so `/opacity` works. */
const token = (name: string) => `rgb(var(--st-${name}) / <alpha-value>)`;

export default {
  darkMode: "class",
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        canvas: token("canvas"),
        surface: {
          DEFAULT: token("surface"),
          raised: token("surface-raised"),
          sunken: token("surface-sunken"),
        },
        line: { DEFAULT: token("line"), strong: token("line-strong") },
        ink: {
          DEFAULT: token("ink"),
          muted: token("ink-muted"),
          subtle: token("ink-subtle"),
          inverse: token("ink-inverse"),
        },
        brand: {
          DEFAULT: token("brand"),
          // `dark`/`light` are the historical hover and tint slots.
          dark: token("brand-strong"),
          light: token("brand-soft"),
          fg: token("on-brand"),
        },
        accent: token("accent"),
        success: token("success"),
        warning: token("warning"),
        danger: token("danger"),
        info: token("info"),
        whatsapp: "#25D366",

        // Raw brand ramp, for the rare place a token is too coarse.
        gold: {
          50: "#FFFCE6",
          100: "#FFF6B8",
          200: "#FFEE7A",
          300: "#FFE43D",
          400: "#FFD700",
          500: "#FACC15",
          600: "#FBBF24",
          700: "#C99700",
          800: "#9A7300",
          900: "#6E5200",
          950: "#3F2E00",
        },
      },
      fontFamily: {
        sans: ["ui-sans-serif", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
        // Headings share the body face; weight and tracking carry the voice.
        display: ["ui-sans-serif", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
      /*
       * The scale runs one step warmer than Tailwind's default at every size.
       *
       * The board is read standing up and at arm's length, not leaned into: the
       * stock 14px body and 12px chrome are a desk-app's sizes and they cost a
       * dispatcher a squint on every row. Shifting the ramp here rather than at
       * the call sites keeps the existing type hierarchy exactly as designed —
       * every `text-sm` in the panel moves together, and the ratios between
       * steps are preserved. Line heights are re-paired rather than scaled, so
       * dense tables gain legibility without gaining rows.
       */
      fontSize: {
        xs: ["0.8125rem", { lineHeight: "1.125rem" }], // 13px — chrome, never prose
        sm: ["0.9375rem", { lineHeight: "1.375rem" }], // 15px — body
        base: ["1.0625rem", { lineHeight: "1.625rem" }], // 17px
        lg: ["1.1875rem", { lineHeight: "1.75rem" }], // 19px — page + card titles
        xl: ["1.375rem", { lineHeight: "1.875rem" }], // 22px
        "2xl": ["1.625rem", { lineHeight: "2.125rem" }], // 26px
        "3xl": ["2rem", { lineHeight: "2.375rem" }], // 32px — the counts
        "4xl": ["2.5rem", { lineHeight: "2.75rem" }], // 40px
        "5xl": ["3.25rem", { lineHeight: "1" }], // 52px — the hero's alarm figure
      },
      boxShadow: {
        sm: "0 1px 2px 0 rgb(var(--st-shadow) / var(--st-shadow-alpha))",
        DEFAULT: "0 2px 8px -2px rgb(var(--st-shadow) / var(--st-shadow-alpha))",
        md: "0 8px 24px -6px rgb(var(--st-shadow) / var(--st-shadow-alpha))",
        glow: "0 0 0 1px rgb(var(--st-brand) / 0.35), 0 8px 32px -8px rgb(var(--st-brand) / 0.45)",
      },
      ringColor: { DEFAULT: token("ring") },
    },
  },
  plugins: [],
} satisfies Config;
