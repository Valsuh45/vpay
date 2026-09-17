// @vitest-environment jsdom
/**
 * The one behaviour that makes issue #195 work: a successful session read on
 * `/c/{id}/redirect` marks this tab as a sheet's redirect leg and navigates
 * to the rail URL the server stored — never to anything the URL supplied.
 */
import { render, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { recallRedirectLeg } from "../lib/redirect-leg";
import { makeBranding } from "../testing/fixtures";
import { RedirectClient } from "./redirect-client";

const SESSION_ID = "cs_123";
const RAIL_URL = "https://orange.example/pay/abc";

function sessionEnvelope(nextAction: unknown) {
  return {
    object: "checkout.session",
    id: SESSION_ID,
    payment_intent: {
      object: "payment_intent",
      id: "pi_123",
      status: "requires_action",
      next_action: nextAction,
    },
  };
}

function stubFetch(body: unknown) {
  vi.stubGlobal(
    "fetch",
    vi.fn(
      () =>
        new Response(JSON.stringify(body), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
    ),
  );
}

describe("RedirectClient", () => {
  let assignMock: ReturnType<typeof vi.fn>;
  const originalLocation = window.location;

  beforeEach(() => {
    // `window.location` is configurable in jsdom; replace it with a mock so
    // the page's navigation (`location.assign`) and its credential read
    // (`location.search`/`location.hash`) are observable and controllable.
    assignMock = vi.fn();
    Object.defineProperty(window, "location", {
      value: {
        search: "?key=pk_test_1",
        hash: "#cs_123_secret_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        assign: assignMock,
      },
      configurable: true,
    });
  });

  afterEach(() => {
    Object.defineProperty(window, "location", {
      value: originalLocation,
      configurable: true,
    });
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    window.sessionStorage.clear();
  });

  it("marks the tab as a redirect leg, then navigates to the rail URL the server stored", async () => {
    stubFetch(
      sessionEnvelope({
        type: "redirect_to_url",
        redirect_to_url: { url: RAIL_URL },
      }),
    );

    render(
      <RedirectClient
        sessionId={SESSION_ID}
        apiBaseUrl="https://api.example"
        initialLocale="fr"
        branding={makeBranding()}
      />,
    );

    await waitFor(() => expect(assignMock).toHaveBeenCalledWith(RAIL_URL));
    // The marker is written BEFORE the navigation, so the return page the
    // rail redirects to suppresses its own outcome.
    expect(recallRedirectLeg(window.sessionStorage, SESSION_ID)).toBe(true);
  });

  it("never navigates when the session names no redirect, and does not mark the tab", async () => {
    stubFetch(sessionEnvelope(null));

    render(
      <RedirectClient
        sessionId={SESSION_ID}
        apiBaseUrl="https://api.example"
        initialLocale="fr"
        branding={makeBranding()}
      />,
    );

    // Give the async read time to settle.
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(assignMock).not.toHaveBeenCalled();
    expect(recallRedirectLeg(window.sessionStorage, SESSION_ID)).toBe(false);
  });
});
