import { headers } from "next/headers";

import { RedirectClient } from "../../../../src/components/redirect-client";
import { pickLocale } from "../../../../src/i18n/index";
import { browserApiBaseUrl } from "../../../../src/lib/env";

/**
 * The redirect-leg page, `/c/{cs_id}/redirect?key={pk}#{client_secret}` —
 * issue #195.
 *
 * The vpay-controlled surface a native sheet opens in the payer's browser
 * instead of a redirect rail's raw URL. It reads the session for the
 * intent's credential, reads the intent for the rail's URL, marks this tab
 * as a sheet's redirect leg, and sends the browser to the rail; when the
 * rail returns the payer to `/c/{id}/return`, that page suppresses its own
 * outcome because the sheet reports it. See `src/lib/redirect.ts` for the
 * reasoning — including why the rail URL comes from the intent read and not
 * from the session — and `middleware.ts` for why this page needs no origin
 * lookup (it never frames and never `postMessage`s).
 *
 * No `branding` is passed: neither screen this page can render carries a
 * merchant name, an amount or a support line, so there is nothing for
 * `branding.yaml` to reach.
 *
 * `force-dynamic` for the same reason as every other route here; the
 * `client_secret` arrives in the fragment, which never reaches this server
 * component (D6).
 */
export const dynamic = "force-dynamic";

export default async function CheckoutRedirectPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const requestHeaders = await headers();
  return (
    <RedirectClient
      sessionId={id}
      apiBaseUrl={browserApiBaseUrl()}
      initialLocale={pickLocale(requestHeaders.get("accept-language"))}
    />
  );
}
