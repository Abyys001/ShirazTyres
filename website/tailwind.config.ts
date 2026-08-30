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
        sans: ["var(--font-sans)", "ui-sans-serif", "system-ui", "Segoe UI", "Roboto", "sans-serif"],
        display: ["var(--font-display)", "var(--font-sans)", "ui-sans-serif", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
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
