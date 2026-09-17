// @vitest-environment jsdom
/**
 * The one behaviour that makes issue #195 work: `/c/{id}/redirect` marks
 * this tab as a sheet's redirect leg and navigates to the rail URL **the
 * server** holds — never to anything the page's own URL supplied.
 *
 * Driven against `src/testing/browser-stub.ts`, a real `node:http` server,
 * rather than a patched `fetch`. That is not ceremony here, it is the whole
 * point: the first version of this page read `next_action` off the session
 * response, which the server never puts there, and a hand-written `fetch`
 * stub that answered one certified a page that would have sent no payer to
 * any rail. A test may only assert a shape the server actually sends.
 */
import { cleanup, render, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { recallRedirectLeg } from "../lib/redirect-leg";
import { startCheckoutStub, type CheckoutStub } from "../testing/browser-stub";
import { RedirectClient } from "./redirect-client";

const RAIL_URL = "https://orange.example/pay/abc";

let open: CheckoutStub | null = null;
let restoreLocation: (() => void) | null = null;

afterEach(async () => {
  // Explicit: `globals: false` in `vitest.config.ts` means testing-library
  // registers no automatic cleanup, so a second render would otherwise find
  // the first one's DOM still mounted.
  cleanup();
  await open?.close();
  open = null;
  restoreLocation?.();
  restoreLocation = null;
  window.sessionStorage.clear();
});

/**
 * Replaces `window.location` with a recorder.
 *
 * `location.assign` and the credential read (`location.search`/`.hash`) are
 * the two things this page does with it, and jsdom makes the property
 * configurable, so both are observable without patching the component.
 */
function stubLocation(stub: CheckoutStub): { assigned: string[] } {
  const original = window.location;
  const assigned: string[] = [];
  Object.defineProperty(window, "location", {
    value: {
      search: `?key=${stub.publishableKey}`,
      hash: `#${stub.sessionSecret}`,
      assign: (url: string) => assigned.push(url),
    },
    configurable: true,
  });
  restoreLocation = () =>
    Object.defineProperty(window, "location", {
      value: original,
      configurable: true,
    });
  return { assigned };
}

/** What the sheet has already done by the time this page loads: confirmed a redirect rail. */
async function confirmOrange(stub: CheckoutStub): Promise<void> {
  const response = await fetch(
    `${stub.url}/v1/browser/payment_intents/${"pi_test_stub0000000000000001"}/confirm`,
    {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        key: stub.publishableKey,
        client_secret: stub.intentSecret,
        "payment_method_data[type]": "orange_money",
      }).toString(),
    },
  );
  expect(response.status).toBe(200);
}

function renderPage(stub: CheckoutStub) {
  return render(
    <RedirectClient
      sessionId={stub.sessionId}
      apiBaseUrl={stub.url}
      initialLocale="fr"
    />,
  );
}

describe("RedirectClient", () => {
  it("marks the tab as a redirect leg, then navigates to the rail URL the server stored", async () => {
    const stub = await startCheckoutStub({
      paymentMethodTypes: ["orange_money"],
      redirectUrl: RAIL_URL,
      // The poll must not settle the intent out of `requires_action` before
      // this page reads it.
      pollsBeforeTerminal: 5,
    });
    open = stub;
    await confirmOrange(stub);
    const { assigned } = stubLocation(stub);

    renderPage(stub);

    await waitFor(() => expect(assigned).toEqual([RAIL_URL]));
    // The marker is written BEFORE the navigation, so the return page the
    // rail redirects to suppresses its own outcome.
    expect(recallRedirectLeg(window.sessionStorage, stub.sessionId)).toBe(true);
  });

  it("reads the rail URL from the intent route, because the session route never carries one", async () => {
    const stub = await startCheckoutStub({
      paymentMethodTypes: ["orange_money"],
      redirectUrl: RAIL_URL,
      pollsBeforeTerminal: 5,
    });
    open = stub;
    await confirmOrange(stub);
    const { assigned } = stubLocation(stub);

    renderPage(stub);

    await waitFor(() => expect(assigned).toEqual([RAIL_URL]));
    // The session read answers the intent's credential and a null
    // `next_action`; the intent read answers the rail URL. A page that
    // stopped at the first would never have got here.
    const paths = stub.urls().map((url) => url.split("?")[0] ?? url);
    expect(paths).toContain(`/v1/browser/checkout/sessions/${stub.sessionId}`);
    expect(
      paths.some((path) => path.startsWith("/v1/browser/payment_intents/")),
    ).toBe(true);
  });

  it("never navigates when the intent names no redirect, and does not mark the tab", async () => {
    // Never confirmed: `requires_payment_method`, no `next_action` anywhere.
    const stub = await startCheckoutStub({
      paymentMethodTypes: ["orange_money"],
      redirectUrl: RAIL_URL,
    });
    open = stub;
    const { assigned } = stubLocation(stub);

    const { findByText } = renderPage(stub);

    // The neutral screen is the page's only other outcome, so waiting for it
    // is waiting for both reads to have settled — no arbitrary sleep.
    await findByText("Retour à l’application");
    expect(assigned).toEqual([]);
    expect(recallRedirectLeg(window.sessionStorage, stub.sessionId)).toBe(
      false,
    );
  });

  it("navigates nowhere on a credential the URL does not carry", async () => {
    const stub = await startCheckoutStub({
      paymentMethodTypes: ["orange_money"],
      redirectUrl: RAIL_URL,
      pollsBeforeTerminal: 5,
    });
    open = stub;
    await confirmOrange(stub);
    const original = window.location;
    const assigned: string[] = [];
    // A crafted link: the rail's own URL offered in the query and in the
    // fragment, and no session credential. Nothing on this page reads
    // either, so there is nothing to follow.
    Object.defineProperty(window, "location", {
      value: {
        search: `?url=${encodeURIComponent("https://evil.example/")}`,
        hash: `#https://evil.example/`,
        assign: (url: string) => assigned.push(url),
      },
      configurable: true,
    });
    restoreLocation = () =>
      Object.defineProperty(window, "location", {
        value: original,
        configurable: true,
      });

    const before = stub.urls().length;
    const { findByText } = renderPage(stub);

    await findByText("Retour à l’application");
    expect(assigned).toEqual([]);
    // Not one request either: without a credential there is no session to
    // read, so the page never even asks.
    expect(stub.urls()).toHaveLength(before);
  });
});
