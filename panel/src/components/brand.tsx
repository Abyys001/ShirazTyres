import Image from "next/image";

import logo from "@/brand/logo.png";
import logoDark from "@/brand/logo-dark.png";

/**
 * The ShirazTyres logo.
 *
 * Two files rather than one tinted asset: the mark is navy and gold, and navy on
 * the panel's ink canvas is a hole. Both are rendered and the theme hides one, so
 * the swap is CSS — no JavaScript, and nothing to flash on first paint.
 *
 * `className` sets the height only; the width follows the artwork.
 */
export function BrandMark({ className = "h-8" }: { className?: string }) {
  return (
    // One element to the caller, whatever the theme: two bare images would be two
    // children, and a `space-y` parent would then indent whichever one is showing.
    <span className={`inline-flex ${className}`}>
      <Image src={logo} alt="" loading="eager" className="h-full w-auto dark:hidden" />
      <Image src={logoDark} alt="" loading="eager" className="hidden h-full w-auto dark:block" />
    </span>
  );
}

/**
 * Logo plus wordmark. `Shiraz` carries the ink, `Tyres` the gold — the same
 * two-tone split the apps use, so the panel and the phones read as one brand.
 */
export function BrandLockup({
  className = "",
  markClassName = "h-8",
  wordClassName = "text-lg",
}: {
  className?: string;
  markClassName?: string;
  wordClassName?: string;
}) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <BrandMark className={markClassName} />
      <span className={`font-display font-bold leading-none tracking-tight ${wordClassName}`}>
        <span className="text-ink">Shiraz</span>
        <span className="text-brand">Tyres</span>
      </span>
    </span>
  );
}
