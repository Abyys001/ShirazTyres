import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";

import { Providers } from "@/components/providers";

import "./globals.css";

/**
 * Sora sets the headline voice; Inter carries the UI; mono is for VRMs and money.
 * The faces are vendored (variable, subset to latin + latin-ext) rather than pulled
 * from `next/font/google`, so the build needs no egress to fonts.googleapis.com.
 */
const display = localFont({
  src: "../fonts/Sora-Variable.woff2",
  weight: "400 700",
  style: "normal",
  display: "swap",
  variable: "--font-display",
  fallback: ["ui-sans-serif", "system-ui", "sans-serif"],
});

const sans = localFont({
  src: "../fonts/Inter-Variable.woff2",
  weight: "400 700",
  style: "normal",
  display: "swap",
  variable: "--font-sans",
  fallback: ["ui-sans-serif", "system-ui", "-apple-system", "Segoe UI", "sans-serif"],
});

const mono = localFont({
  src: "../fonts/JetBrainsMono-Variable.woff2",
  weight: "400 700",
  style: "normal",
  display: "swap",
  variable: "--font-mono",
  fallback: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
});

export const metadata: Metadata = {
  title: "ShirazTyres — emergency tyre call-out",
  description: "Punctured or blown out in London? A technician comes to you.",
};

export const viewport: Viewport = {
  themeColor: "#0B1315",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-GB" className={`dark ${display.variable} ${sans.variable} ${mono.variable}`}>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
