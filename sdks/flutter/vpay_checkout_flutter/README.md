# vpay_checkout_flutter

A payer-facing checkout surface for vpay: opens vpay's hosted checkout page
in a native window and answers a typed [`VpayCheckoutResult`] once a payment
intent actually settles. Design:
[`docs/plans/2026-09-13-flutter-plugin.md`](../../../docs/plans/2026-09-13-flutter-plugin.md).
Decisions: [ADR-0021](../../../docs/adr/0021-flutter-checkout-plugin.md).

**Status (2026-09-13): pure-Dart core only.** No `android/`, `ios/`,
`macos/` implementation exists in this repository yet — every call to
[`VpayCheckoutPlatform.instance`] throws `UnimplementedError` until a
platform host registers itself (Lane C of
[the implementation brief](../../../docs/plans/2026-09-13-flutter-plugin-brief.md)).
See [`docs/sdks/parity.md`](../../../docs/sdks/parity.md)'s table for this
package for what is and is not proven today.

## What this is not

`POST /v1/checkout/sessions` stays on the merchant's own server, exactly as
it does for a web integration. This package never holds a merchant token, a
private key, or an `Authorization` header — only a publishable key and one
session's own short-lived credentials, read out of the `url` the merchant's
server already returned.

**`VpayCheckoutResult.succeeded` is a UI fact, not a settlement.** A
merchant's server must still act on `payment_intent.succeeded` from the
webhook — this package never reads an outcome off a URL a merchant's own
site controls (design doc D1); it polls
`GET /v1/browser/payment_intents/{id}` and answers what that says.

## App Store and Play policy — read this before shipping `externalBrowser`

Raised by the maintainer: _"won't apple flag us? Even if we're using a
browser, technically we're still in app right?"_ (design doc D9).

**The rule keys on what is sold, not on where the payment UI lives.** The
in-app `WebView` (the default `VpayCheckoutMode.inApp`) and
`VpayCheckoutMode.externalBrowser` are treated identically by both stores;
neither is a way around anything.

- **Selling a physical good, or a service consumed outside the app?** You
  are required to use a method other than in-app purchase — Apple's App
  Store Review Guidelines, **3.1.3(e)**, verbatim:

  > If your app enables people to purchase physical goods or services that
  > will be consumed outside of the app, you must use purchase methods other
  > than in-app purchase to collect those payments, such as Apple Pay or
  > traditional credit card entry.

  This plugin is exactly such a method. Google Play is the same shape from
  the other side: Play Billing is for digital items only.

- **Unlocking something *within* the app** — a subscription, in-app credits,
  game levels, premium content, a digital gift card? Apple's **3.1.1**
  requires In-App Purchase for that, and a vpay checkout for any of it is a
  rejection — in-app `WebView` or `externalBrowser` alike.

- **The trap: `externalBrowser` does not move a digital-goods app out of
  3.1.1.** Apple's **3.1.1(a)** goes further: outside the United States
  storefront, an app "may not include buttons, external links, or other
  calls to action that direct customers to purchasing mechanisms other than
  in-app purchase" without a region-limited StoreKit entitlement. For a
  digital-goods merchant, opening Safari via `externalBrowser` is not
  neutral — it can itself be the violation.

This is a reading of the published guidelines on 2026-09-13, not legal
advice and not a review outcome — Apple's reviewers decide case by case, and
both stores' rules move. See
[`docs/flows/mobile-checkout.md`](../../../docs/flows/mobile-checkout.md)
for the fuller quotes and sources read.

## Credentials and redaction (D6)

- `toString()` is overridden on every type holding a session URL, a session
  secret or an intent secret (`PaymentIntent`, `CheckoutSession`) —
  `[N chars redacted]`, never the value.
- No `print`, `debugPrint` or `log` call anywhere in `lib/` — asserted by
  `test/no_logging_test.dart`, which reads the package's own source.
- `BrowserClient` refuses a non-`https` base URL unless the named
  `allowInsecureBaseUrl` opt-in is passed — for `compose.demo.yml` only,
  never inferred from a debug build.

## Development

```bash
just install-flutter   # flutter pub get
just analyze-flutter   # dart analyze --fatal-infos
just test-flutter      # flutter test (unit tests only, no device)
```

None of the three is in `just ci` yet (D-M3) — see `docs/sdks/parity.md`'s
dated ⛔ row.
