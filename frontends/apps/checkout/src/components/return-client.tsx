/**
 * The client half of `/c/{id}/return`.
 *
 * Top-level in both modes: the payer got here by a full-page redirect from
 * the rail, so there is no *parent* to talk to and `window.location.assign`
 * is the forward — unless this window is a popup, which is the one case
 * where there is still an **opener**. See the last paragraph.
 *
 * **No timer navigates**, for the same reason as the payment page: the
 * outcome screen has a button and nothing else. This page carried the same
 * five-second countdown until 2026-09-06.
 *
 * There is no page memory here either. The return trip has no form to
 * prefill, and a page that cannot confirm has nothing to remember.
 *
 * It CAN have a peer, though, since 2026-09-06: a popup checkout that went
 * through a redirect rail ends here, and the merchant's window has to hear
 * about it. The opener is pinned by `soleOrigin` rather than by the referrer,
 * because the referrer here is the rail's — see `origins.ts`.
 */
"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { Branding } from "../config/settings";
import { translator, type Locale } from "../i18n/index";
import { BrowserCheckoutApi } from "../lib/api";
import { decideReturnEntry } from "../lib/entry";
import { forwardKindFor, forwardTarget } from "../lib/forward";
import { createFrameChannel, type FrameChannel } from "../lib/frame";
import { recallPublishableKey } from "../lib/link";
import { clearRedirectLeg, recallRedirectLeg } from "../lib/redirect-leg";
import {
  RETURN_INITIAL_STATE,
  ReturnController,
  type ReturnState,
} from "../lib/return";
import { ReturnView } from "./return-view";

export interface ReturnClientProps {
  sessionId: string;
  apiBaseUrl: string;
  initialLocale: Locale;
  /** `branding.yaml`, read at container start. The return page carries the same mark as the payment page. */
  branding: Branding;
  /**
   * The merchant's registered origins, resolved server-side by
   * `middleware.ts`. Used for one thing only: pinning an opener when this
   * page is the last screen of a popup checkout.
   */
  allowedOrigins: readonly string[];
}

export function ReturnClient(props: ReturnClientProps) {
  const [locale, setLocale] = useState<Locale>(props.initialLocale);
  const [state, setState] = useState<ReturnState>(RETURN_INITIAL_STATE);
  const controllerRef = useRef<ReturnController | null>(null);

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  useEffect(() => {
    const redirectLeg = recallRedirectLeg(
      window.sessionStorage,
      props.sessionId,
    );
    if (redirectLeg) {
      // Issue #195: this tab is a native sheet's redirect leg. The sheet is
      // the outcome reporter, so this page renders a neutral "returning to
      // the app" screen and never starts a controller — no poll, no outcome.
      // The marker is cleared so a later normal web checkout in the same tab
      // is not suppressed. Checked BEFORE the entry decision so a redirect
      // leg always renders the neutral screen, whatever the shape of the
      // return URL the rail handed back (a malformed one must not re-surface
      // a foreign error screen on top of the sheet's outcome).
      clearRedirectLeg(window.sessionStorage, props.sessionId);
      // The neutral screen is the one setState on the synchronous entry path
      // — the effect's real work (the controller) is async, so this is a
      // React-lint false positive worth the one-line reason.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setState({ name: "redirect_leg" });
      return;
    }
    const decision = decideReturnEntry({
      search: window.location.search,
      rememberedKey: recallPublishableKey(
        window.sessionStorage,
        props.sessionId,
      ),
      hasOpener: window.opener !== null && window.opener !== undefined,
      allowedOrigins: props.allowedOrigins,
    });
    if (decision.kind === "error") {
      // REAL finding, same shape as `checkout-client.tsx`: the return trip's
      // token is read from the URL, which only the browser can do.
      setState({ name: "error", error: { code: decision.code } });
      return;
    }
    let channel: FrameChannel | null = null;
    if (decision.openerOrigin !== null) {
      channel = createFrameChannel({
        win: window,
        peer: "opener",
        parentOrigin: decision.openerOrigin,
      });
    }
    const controller = new ReturnController({
      sessionId: props.sessionId,
      credentials: { key: decision.key, returnToken: decision.returnToken },
      api: new BrowserCheckoutApi({ baseUrl: props.apiBaseUrl }),
      navigate: (url) => window.location.assign(url),
      closeWindow: () => window.close(),
      opener: () => window.opener as Window | null,
      channel,
    });
    controllerRef.current = controller;
    const unsubscribe = controller.subscribe(setState);
    setState(controller.state);
    void controller.start();
    return () => {
      unsubscribe();
      channel?.dispose();
      controllerRef.current = null;
    };
  }, [props.allowedOrigins, props.apiBaseUrl, props.sessionId]);

  const destination = useMemo(() => {
    if (state.name !== "outcome") {
      return null;
    }
    return forwardTarget(
      state.context.session,
      forwardKindFor(state.context.session, state.kind === "succeeded"),
    );
  }, [state]);

  const onReturnToMerchant = useCallback(() => {
    if (destination !== null) {
      controllerRef.current?.forward(destination);
    }
  }, [destination]);

  const t = useMemo(() => translator(locale), [locale]);

  return (
    <ReturnView
      state={state}
      t={t}
      locale={locale}
      branding={props.branding}
      destination={destination}
      onReturnToMerchant={onReturnToMerchant}
      onLocaleChange={setLocale}
    />
  );
}
