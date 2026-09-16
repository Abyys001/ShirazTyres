/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: "standalone",
  eslint: { ignoreDuringBuilds: false },

  /*
   * The compose panel runs `next dev` as root against a bind mount of this
   * directory, so its build output lands in the working tree owned by root. A
   * second `next dev` on the host — the usual way to point the panel at a
   * backend running outside the stack — then cannot write `.next` and dies with
   * EACCES on a file it did not create.
   *
   * Setting NEXT_DIST_DIR gives that second server its own output directory and
   * the two stop fighting. Unset, nothing changes.
   */
  distDir: process.env.NEXT_DIST_DIR || ".next",
};

export default nextConfig;
