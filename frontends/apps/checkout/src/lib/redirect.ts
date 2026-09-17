/**
 * The `/c/{id}/redirect` page — a vpay-controlled surface the native sheet
 * opens in the payer's browser instead of a redirect rail's raw URL (issue
 * #195).
 *
 * Its whole job is to be a controlled start: it reads the session from the
 * server, takes the rail's URL from the **intent** (`next_action.redirect_to_url`),
 * marks this tab as a sheet's redirect leg
 * (`redirect-leg.ts`'s `rememberRedirectLeg`), and sends the browser to the
 * rail. When the rail redirects the payer back to `/c/{id}/return`, that page
 * sees the marker and suppresses its own outcome — the sheet reports the
 * outcome, so the payer sees it once.
 *
 * # Why the rail URL is read, never passed
 *
 * The sheet already knows the rail URL (it confirmed the intent and read
 * `next_action.redirect_to_url`). It is deliberately not passed here as a
 * parameter: this page is on vpay's origin, and a page that trusted a
 * caller-supplied `?url=` (or `#railUrl=`) would be an **open redirect** — a
 * crafted link would send a payer who clicked it to an arbitrary site from a
 * payment origin. Reading the session answers the rail URL from the server,
 * where only the legitimate redirect target can be.
 *
 * A fragment carries no `key`, so this page takes the publishable key in the
 * query (public) and the session's `client_secret` in the fragment (D6 —
 * never in a log or a `Referer`), the same credential shape `link.ts`
 * documents for the hosted page.
 */
import { parsePageCredentials } from "./link";
import type { CheckoutErrorCode } from "./types";

export type RedirectLegDecision =
  | { kind: "ready"; key: string; clientSecret: string }
  | { kind: "error"; code: CheckoutErrorCode };

/**
 * Reads the page's own credentials off `location.search`/`location.hash`.
 *
 * Same rule as the hosted page: the secret lives in the fragment, the key in
 * the query. Anything missing or unparseable is `error`, which the client
 * shows as a neutral screen rather than a payment form.
 */
export function decideRedirectLegEntry(input: {
  search: string;
  hash: string;
}): RedirectLegDecision {
  const credentials = parsePageCredentials(input.search, input.hash);
  if (credentials.key === null) {
    return { kind: "error", code: "error.missing_key" };
  }
  if (credentials.clientSecret === null) {
    return { kind: "error", code: "error.missing_secret" };
  }
  return {
    kind: "ready",
    key: credentials.key,
    clientSecret: credentials.clientSecret,
  };
}
