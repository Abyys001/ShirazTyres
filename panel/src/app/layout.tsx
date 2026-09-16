import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";

import { Providers } from "@/components/providers";

import "./globals.css";

/**
 * Headings and body are set in `ui-sans-serif` — the reader's own UI face, which
 * ships with their OS and so costs nothing to load. Only mono is vendored, for
 * the tabular figures VRMs and money line up in; it is a local file rather than
 * `next/font/google`, so the build needs no egress to fonts.googleapis.com.
 */
const mono = localFont({
  src: "../fonts/JetBrainsMono-Variable.woff2",
  weight: "400 700",
  style: "normal",
  display: "swap",
  variable: "--font-mono",
  fallback: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
});

export const metadata: Metadata = {
  title: "ShirazTyres Panel",
  description: "Emergency tyre call-outs, drivers and vehicle lookups.",
};

export const viewport: Viewport = {
  themeColor: "#0B1315",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-GB" className={`dark ${mono.variable}`}>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
