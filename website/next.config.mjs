/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: "standalone",
  eslint: { ignoreDuringBuilds: false },

  // Same reason as the panel: the compose container runs `next dev` as root
  // against a bind mount of this directory, so a second server on the host
  // needs its own output directory or it dies with EACCES. Unset, nothing
  // changes.
  distDir: process.env.NEXT_DIST_DIR || ".next",
};

export default nextConfig;
