/**
 * The client half of `/c/{id}/redirect` — the vpay-controlled surface a
 * native sheet opens in the payer's browser instead of a redirect rail's raw
 * URL (issue #195).
 *
 * Everything here needs a browser: reading the fragment, calling the API,
 * writing the redirect-leg marker to `sessionStorage`, and performing the
 * navigation. The decision of *what to do* is imported
 * (`decideRedirectLegEntry`, `intentClientSecretOf` and `redirectUrlOf`), so
 * this file is wiring, not policy.
 *
 * # What it does, and what it never does
 *
 * It reads the session for the intent's credential, reads the **intent** for
 * the rail's URL, marks this tab as a sheet's redirect leg, and navigates to
 * the rail. It never navigates to a URL the caller supplied, so it cannot be
 * turned into an open redirect — and it never reads `next_action` off the
 * session, which would answer `null` on every real deployment. Both are
 * `redirect.ts`'s module doc.
 *
 * # What the payer sees
 *
 * While the reads and the navigation are in flight it shows a loading
 * screen — never the "you can close this window" copy, because that copy
 * invites the payer to close *before* the rail has opened. Only if the
 * redirect cannot happen at all (a broken credential, an unreadable session
 * or intent, an intent with no redirect) does it fall through to the neutral
 * "returning to the app" screen, which is accurate there: the rail was never
 * opened, and the sheet's poll reports what actually happened.
 *
 * It renders no branding. The two screens it can show carry no merchant
 * name, no amount and no support line — there is nothing here for a brand to
 * be applied to, and the sheet behind this window is already wearing the
 * host app's own theme.
 */
"use client";

import { loadStripe } from "@vaam-apps/vpay-stripe-js";
import { useEffect, useMemo, useState } from "react";

import { translator, type Locale } from "../i18n/index";
import { BrowserCheckoutApi } from "../lib/api";
import { redirectUrlOf } from "../lib/controller";
import { decideRedirectLegEntry, intentClientSecretOf } from "../lib/redirect";
import { rememberRedirectLeg } from "../lib/redirect-leg";
import { RedirectLegNeutral, StatusPanel } from "./screens";

export interface RedirectClientProps {
  sessionId: string;
  /** `NEXT_PUBLIC_VPAY_API_URL` — the origin `/v1/browser/...` hangs off. */
  apiBaseUrl: string;
  initialLocale: Locale;
}

export function RedirectClient(props: RedirectClientProps) {
  const [locale] = useState<Locale>(props.initialLocale);
  // `false` while the session read / navigation is in flight (show a loading
  // screen); `true` once the redirect has been given up on (show the neutral
  // screen — the sheet will report the outcome).
  const [terminal, setTerminal] = useState(false);

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  useEffect(() => {
    const decision = decideRedirectLegEntry({
      search: window.location.search,
      hash: window.location.hash,
    });
    if (decision.kind === "error") {
      // No usable credential — the sheet handed a broken URL. There is
      // nothing to redirect to.
      // eslint-disable-next-line react-hooks/set-state-in-effect -- the first render is synchronous and this is the page's entry decision.
      setTerminal(true);
      return;
    }

    let cancelled = false;
    void (async () => {
      const api = new BrowserCheckoutApi({ baseUrl: props.apiBaseUrl });
      const session = await api.readSession(props.sessionId, {
        key: decision.key,
        clientSecret: decision.clientSecret,
      });
      if (cancelled) {
        return;
      }
      // The session read answers the **intent's** credential, never a
      // `next_action` — see `redirect.ts`'s module doc for why reading one
      // off this response would be a page that never redirects anybody.
      const intentSecret = session.ok
        ? intentClientSecretOf(session.value)
        : null;
      if (intentSecret === null) {
        setTerminal(true);
        return;
      }
      let retrieved;
      try {
        const stripe = await loadStripe(decision.key, {
          baseUrl: props.apiBaseUrl,
        });
        retrieved = await stripe.retrievePaymentIntent(intentSecret);
      } catch {
        // `loadStripe` rejects only on a blank key or base URL — the same
        // integration mistake `checkout-client.tsx` handles, and not a payer
        // this page can send anywhere.
        setTerminal(true);
        return;
      }
      if (cancelled) {
        return;
      }
      const url =
        retrieved.paymentIntent === undefined
          ? null
          : redirectUrlOf(retrieved.paymentIntent);
      if (url === null) {
        // The intent could not be read, or it names no redirect — the rail
        // was already consumed, say. There is nothing to redirect to.
        setTerminal(true);
        return;
      }
      // Mark this tab as a sheet's redirect leg BEFORE navigating, so the
      // return page (which the rail will redirect to) suppresses its own
      // outcome. The marker survives the rail's cross-origin redirect in
      // this same tab (`redirect-leg.ts`'s module doc).
      rememberRedirectLeg(window.sessionStorage, props.sessionId);
      window.location.assign(url);
    })();

    return () => {
      cancelled = true;
    };
  }, [props.apiBaseUrl, props.sessionId]);

  const t = useMemo(() => translator(locale), [locale]);

  if (terminal) {
    return <RedirectLegNeutral t={t} />;
  }
  // The redirect is being prepared or is in flight — never the "close this
  // window" copy, which would invite the payer to close before the rail
  // opens (see this file's module doc).
  return (
    <StatusPanel
      t={t}
      screen="redirect_leg"
      title={t("state.loading")}
      body={null}
    />
  );
}
