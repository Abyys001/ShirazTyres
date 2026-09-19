/**
 * Whether this panel shows its development aids.
 *
 * The seeded sign-in row, the one-tap dev login and the Apps page (which links
 * to localhost ports and to builds anyone can sign into) do not belong on a
 * panel the public can reach. They were each gated on
 * `NODE_ENV !== "production"`, which worked only for as long as "development
 * build" and "not a real deployment" meant the same thing — and they stop
 * meaning the same thing the moment a staging server is built for production so
 * that it is quick enough to use.
 *
 * One flag, asked explicitly, defaulting to the old behaviour. A real
 * production panel sets nothing and keeps them off; a staging box that wants
 * them sets `NEXT_PUBLIC_DEV_TOOLS=true` and takes the consequences knowingly.
 *
 * `NEXT_PUBLIC_` because the login screen and the navigation rail are client
 * components, so the value has to survive into the browser bundle. It is a
 * boolean about this deployment, not a secret.
 */
export const DEV_TOOLS =
  (process.env.NEXT_PUBLIC_DEV_TOOLS ??
    (process.env.NODE_ENV === "production" ? "false" : "true")).toLowerCase() === "true";
