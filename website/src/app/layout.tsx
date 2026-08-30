import type { Metadata, Viewport } from "next";
import { Inter, JetBrains_Mono, Sora } from "next/font/google";

import { Providers } from "@/components/providers";

import "./globals.css";

/** Sora sets the headline voice; Inter carries the UI; mono is for VRMs and money. */
const display = Sora({ subsets: ["latin"], weight: ["600", "700"], variable: "--font-display" });
const sans = Inter({ subsets: ["latin"], variable: "--font-sans" });
const mono = JetBrains_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono" });

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
