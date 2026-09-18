/**
 * A marker in `sessionStorage` that lets the return page tell two trips
 * apart that would otherwise land on the same URL.
 *
 * - **A normal web checkout return.** The payer went through the hosted
 *   page (`/c/{id}`), the rail, and came back to `/c/{id}/return`. The
 *   return page is where the outcome is reported — it must render the full
 *   outcome.
 * - **A native sheet's redirect leg (issue #195).** The sheet is the
 *   outcome reporter, the browser is only the redirect handler. The rail
 *   still sends the payer to the same `/c/{id}/return`, but that page must
 *   **not** render a full outcome — the sheet already has, in its own
 *   language and money format, and showing it twice is the bug this module
 *   exists to close.
 *
 * The marker is written by `/c/{id}/redirect` (the vpay-controlled page the
 * sheet opens instead of the rail's raw URL) before it sends the browser to
 * the rail. `sessionStorage` is per-origin and per-tab, so a value written
 * on vpay's origin survives the rail's cross-origin redirect and is still
 * there when the browser returns to vpay's return page in the same tab —
 * the same mechanism `link.ts`'s own `rememberPublishableKey` already
 * proves on this very pair of pages.
 *
 * **A query parameter cannot do this job.** The rail controls the redirect
 * back to the return page and will not echo a vpay-added parameter, so one
 * would never survive the round trip.
 *
 * **A storage failure degrades to the old behaviour, never to a broken
 * payment.** If storage is disabled or partitioned, `recallRedirectLeg`
 * answers `false`, the return page shows the full outcome, and the payer is
 * back to dismissing the duplicate screen — a UX regression, never a
 * correctness one.
 */

/** The per-session key prefix. Not a credential, but stored in the log-free half of the origin for symmetry. */
export const REDIRECT_LEG_STORAGE_PREFIX = "vpay.checkout.redirect_leg.";

/** Marks this tab as a sheet's redirect leg for `sessionId`. */
export function rememberRedirectLeg(
  storage: Storage | null | undefined,
  sessionId: string,
): void {
  try {
    storage?.setItem(`${REDIRECT_LEG_STORAGE_PREFIX}${sessionId}`, "1");
  } catch {
    // Storage disabled or partitioned. The return page then shows the full
    // outcome — the duplicate the marker exists to avoid, never a broken
    // payment (module doc comment).
  }
}

/** Whether `sessionId`'s redirect-leg marker is present in this tab. */
export function recallRedirectLeg(
  storage: Storage | null | undefined,
  sessionId: string,
): boolean {
  try {
    return (
      (storage?.getItem(`${REDIRECT_LEG_STORAGE_PREFIX}${sessionId}`) ??
        null) !== null
    );
  } catch {
    return false;
  }
}

/** Clears the marker, so a later normal web checkout in the same tab is not suppressed. */
export function clearRedirectLeg(
  storage: Storage | null | undefined,
  sessionId: string,
): void {
  try {
    storage?.removeItem(`${REDIRECT_LEG_STORAGE_PREFIX}${sessionId}`);
  } catch {
    // Nothing to clear, and nothing this page can do about it.
  }
}
