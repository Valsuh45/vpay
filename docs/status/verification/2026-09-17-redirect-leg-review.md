# Issue #195 — review of the redirect leg, and the three defects it found

**Dates:** 2026-09-17 (the first two fixes), 2026-09-18 (the re-run, every
number re-measured from scratch) and 2026-09-18 (§3, the third defect, found
when this branch was merged with `origin/master`). **Branch:**
`fix/195-redirect-sheet-suppresses-outcome` (PR #200), which merges cleanly onto
`origin/master` `eb078020` and, for §3 below, onto `84143e1d` (PR #208).
**Host:** macOS (darwin 25.6.0), Flutter 3.48.0-1.0.pre / Dart 3.14 dev, pnpm
9.15, node 24.

This page records a **partial** run: the web and Flutter halves, four
`cargo xtask` gates, and `just test-storybook`. `just ci` was **not** run —
another agent held the Rust build on this host — so nothing here is evidence
about the Rust workspace.

_(This page was titled "the two defects it found" until 2026-09-18. §3 is a
third instance of §2's root cause, on a different page of the same app, and it
was found by this branch's honest stub rather than by reading — which is the
argument for the stub change §2 made.)_

## The defects

The first two were shipped green: `flutter test` 297 / 0, `just test-web` 536 /
1, `dart analyze` clean, CI's `web` job passing. Each one on its own means the
payer's browser never reaches the rail, so the redirect rail was **more**
broken than the duplicate outcome screen the issue reported.

### 1. The leg was built on the API's origin

`SheetController.startRedirect` built `/c/{id}/redirect` on
`BrowserClient.baseUrl`. That is `deployment.public_base_url` — the API, what
`/v1/browser/...` hangs off, `http://localhost:8080` in `compose.demo.yml` and
the default in `sdks/flutter/vpay_checkout_flutter/example/lib/main.dart`.
`/c/{id}`, `/c/{id}/redirect` and `/c/{id}/return` are served by
`frontends/apps/checkout`, a second deployable on `checkout.public_base_url`
(`http://localhost:3080` in the same file). `backends/crates/vpay-api` mounts
no `/c/` route at any prefix.

**Why the test did not see it:** it passed `https://api.example` as the base and
asserted `https://api.example/c/cs_123/redirect?...` came back, which is equally
true of the right origin and the wrong one.

**Fix:** `SheetController` takes `sessionPageUrl`, derived by
`SheetController.sessionPageUrlFrom` from the server-minted session URL
(`{checkout_base}/c/{cs_id}?key=…#…`, minted by `vpay_api::v1::checkout_sessions`
through `vpay-db`'s own `hosted_url`) the sheet already holds and already parses
for its `client_secret`. A deployment path prefix survives it.

### 2. The page read `next_action` from a route that never sends one

`/c/{id}/redirect` called `redirectUrlOf(session.payment_intent)` on the answer
to `GET /v1/browser/checkout/sessions/{id}`. That route renders its expanded
intent with `PaymentIntentObject::try_from(&PaymentIntentRow)`, whose
`next_action` is `None` unconditionally —
`backends/crates/vpay-api/src/model.rs`, "Always `null` here: `next_action` lives
on the charge, not the intent" — and `with_next_action`, the only thing that
attaches one, is called from `v1::payment_intents` alone (`rendered_intent` and
the confirm path). `browser::checkout_sessions`' `retrieve` and
`retrieve_for_return` call neither. So `redirectUrlOf` answered `null` for every
real session and the page rendered its neutral screen instead of redirecting.

**Why the test did not see it:** it stubbed `fetch` with a hand-written envelope
carrying a `next_action` — a shape the server does not produce on that route.

**Fix:** the page reads the session for the **intent's** `client_secret`
(rendered only while the session is `open`) and then
`GET /v1/browser/payment_intents/{id}` through `@vaam-apps/vpay-stripe-js`'s
`retrievePaymentIntent`, the route whose own doc promises "`next_action` on a
redirect rail". The rail URL is still never accepted from the page's own URL, so
the open-redirect property is unchanged, and `redirectUrlOf`'s `http:`/`https:`
scheme check still gates the navigation.

`src/testing/browser-stub.ts` was itself rendering `next_action` on both
checkout-session routes — the one place it diverged from the API, and what made
this invisible to any stub-backed test. It now answers `null` there.

### 3. The hosted page read it off the same route, on a reload (2026-09-18)

Found where this branch met `origin/master` `84143e1d`, and by the stub change
§2 made rather than by reading. PR #199 (`164d566b`, on `master`) gave the
hosted page a `resume_redirect` state for a payer who abandoned a redirect
rail's page and came back: `machine.ts`'s `stateForContext` reduces a
`requires_action` intent to it, with the URL from `redirectUrlOf(intent)`. The
intent it reduces arrives on `GET /v1/browser/checkout/sessions/{id}` — the same
route as §2, with the same `next_action: None`. Its own comment cited
`payment_intents.rs`'s `rendered_intent` as the reason a URL would always be
there, which is the route that does attach one and not the route the intent came
from.

So on a real deployment the reducer fell through to its `waiting` fallback: a
"check your phone" spinner, for a redirect rail that never sees a payer's phone
number, on a payment only the payer can move — until the poll budget dies. That
is the exact screen #199 was written to remove.

**Why the test did not see it:** #199's two cases passed against the stub as it
then was, which rendered `next_action` on the session route. Against §2's honest
stub they fail — and the shape of the failure is a second finding: the controller
falls back to `waiting`, polls `GET /v1/browser/payment_intents/{id}`, and the
stub settles the intent after its poll budget, so the payer lands on a
**succeeded outcome screen for a payment nobody completed**. That is the stub's
own `pollsBeforeTerminal` model, not the server's behaviour, but it is what made
the failure read as `outcome` rather than as `waiting`.

**Fix:** the same two-read ladder, in the controller instead of the page.
`CheckoutController.start` now calls `#withNextAction`, which — only for an
intent the session read answered as `requires_action` with no `next_action` on
it — re-reads the intent with `@vaam-apps/vpay-stripe-js`'s
`retrievePaymentIntent`, using the intent `client_secret` the session read
carries (`redirect.ts`'s `intentClientSecretOf`, the same helper
`redirect-client.tsx` uses). The reducer then sees an intent that names the rail,
and `machine.ts` stays pure — it fetches nothing and its contract is unchanged.

Every failure of the second read leaves the context exactly as the session
answered it, so the reducer's existing `waiting` fallback stands and no state is
invented; `resume_redirect` is still reachable only with a URL the server sent,
and `redirectUrlOf`'s `http:`/`https:` check still gates the navigation.
`start()` is the only place a session read reaches `stateForContext` —
`#announceOutcome`'s re-read dispatches `session_refreshed`, which the reducer
applies only from `outcome` and only to the session half — so this is one call
site, not a pattern to repeat.

**The test that refuses the regression** is a third case in `controller.test.ts`
§ "the Orange redirect", and it fails in both directions (both mutations are in
the table below). It reads the session route itself and asserts what it actually
answers for a `requires_action` intent — `next_action` `null`, and
`redirectUrlOf` of it `null`, so a controller reducing from that response alone
has no URL to offer — and then asserts the request sequence `resumed.start()`
produces, verbatim: `GET /v1/browser/checkout/sessions/{id}` followed by
`GET /v1/browser/payment_intents/{id}`. A controller that went back to reading
`next_action` off the session would make only the first, and a stub that started
rendering one would fail the first assertion. #199's two cases assert the state
and the navigation and are kept as they were; only the comment that explained
the old mechanism was rewritten.

## Mutation checks

Each fix was reverted in place and the suite re-run, so the tests are known to
fail on the defect rather than assumed to. Both mutations were re-run on
2026-09-18 and the results below are that run's own output.

| Mutation                                                                                                                             | Result                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sessionPageUrl: '${widget.baseUrl}/c/cs_123'` in `checkout_sheet.dart`                                                              | `flutter test` 301 passed, **1 failed** — `checkout_sheet_test.dart`'s new case, `Expected: https://checkout.e … Actual: https://api.exampl …`. Every `redirectLegUrlFor` unit test still passes, which is why the widget test exists.                                 |
| `redirect-client.tsx` restored to PR #200's session read                                                                             | `redirect-client.test.tsx` **2 failed / 2 passed**, both failures on "never navigated to the rail" (`assigned` was `[]`, expected `["https://orange.example/pay/abc"]`).                                                                                               |
| §3: `#withNextAction` in `controller.ts` returns the session's context unchanged (an early `return context;` before the intent read) | `controller.test.ts` **3 failed / 29 passed** — #199's two resume cases (`expected 'outcome' to be 'resume_redirect'`, each after ~2 s of real polling) and the new case below.                                                                                        |
| §3: `browser-stub.ts`'s session route restored to `intentObject(true)` — the stub lying again                                        | `controller.test.ts` **1 failed / 31 passed**, on the new case's `expect(read.value.payment_intent.next_action).toBeNull()`: `expected { type: 'redirect_to_url', …(1) } to be null`. The other two pass, which is precisely why they are not sufficient on their own. |

## Commands and results

Measured 2026-09-18 on this branch.

| Command                                               | Result                                                                                                                                                        |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flutter test` (`sdks/flutter/vpay_checkout_flutter`) | **302 passed, 0 skipped, 0 failed** (297 before this review)                                                                                                  |
| `dart analyze --fatal-infos`                          | `No issues found!`                                                                                                                                            |
| `dart format --set-exit-if-changed .`                 | 59 files, 0 changed                                                                                                                                           |
| `just test-web`                                       | checkout **538 passed / 1 skipped** (30 files), dashboard 316 / 1 skipped (31 files), shop 108, stripe-js 146, nodejs 222, config 60, tokens 10, api-client 4 |
| `just test-storybook`                                 | checkout **24 stories** passed (22 before), dashboard 25 — axe with `color-contrast` enabled                                                                  |
| `just lint-web`                                       | exit 0 (eslint `--max-warnings 0`, prettier, `tsc --noEmit` across the workspace)                                                                             |
| `pnpm exec prettier --check` over this PR's own files | clean (the four `.dart` files have no prettier parser and are covered by `dart format`)                                                                       |
| `just verify-ui`                                      | exit 0                                                                                                                                                        |
| `just verify-status`                                  | ok — 1 unimplemented item, declared                                                                                                                           |
| `just verify-links`                                   | ok — 1711 links in 397 tracked markdown files (1707 before this page's own four links)                                                                        |
| `just verify-sdk-parity`                              | ok — 661 proving tests, 37 dated gaps, 35 SDK methods across 39 rows                                                                                          |
| `node vpay-skills/tools/verify-coverage.mjs .`        | ok — 20 skills, 205 paths, 45 feature pages, 0 exempt (baseline `d3a8810b`, 15 commits behind this checkout)                                                  |

**`just fmt-check-web` was not clean, and not because of this branch.**
`origin/master` `eb078020` fails it on `AGENTS.md`, `CHANGELOG.md`,
`deploy/helm/vpay/Chart.yaml` and
`sdks/flutter/vpay_checkout_flutter/pubspec.yaml`, none of which this PR touches;
`just verify-versions` is red there for the same release-please change and does
not exist on this branch at all. Prettier was therefore run over this PR's own
files only, and they are clean.

### The §3 re-run, 2026-09-18

A second, narrower run on the merge of this branch's head `a61fa919` with
`origin/master` `84143e1d` (PR #208) — the tree §3 was found on and fixed on.
The numbers above are **not** superseded; they were measured on a different
tree and both are kept.

| Command                                                             | Result                                                                                                                                                                                        |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `just test-web`                                                     | checkout **556 passed / 1 skipped** (30 files), dashboard 316 / 1 skipped (31 files), shop 108, stripe-js 146, nodejs 222, config 60, tokens 10, api-client 4 — exit 0                        |
| `pnpm exec vitest run src/lib/controller.test.ts` before the §3 fix | **2 failed / 29 passed** — `expected { name: 'outcome', …(4) } to match object { name: 'resume_redirect', …(1) }`, and `expected 'outcome' to be 'resume_redirect'`; ~2 s each, spent polling |
| `just lint-web`                                                     | exit 0 (eslint `--max-warnings 0`, prettier, `tsc --noEmit` across the workspace)                                                                                                             |
| `just verify-ui`                                                    | exit 0                                                                                                                                                                                        |
| `just verify-status`                                                | ok — 1 unimplemented item, all declared in `docs/status.md`, all still in shipping code                                                                                                       |
| `just verify-links`                                                 | ok — 1719 links in 400 tracked markdown files                                                                                                                                                 |
| `pnpm exec prettier --check` over this change's own files           | clean                                                                                                                                                                                         |

`just test-storybook` was **not** re-run for §3 and is not evidence about it:
this change touches `src/lib/` and `src/testing/` only — no screen, no story,
no theme. `just ci` and the Rust workspace were not run either, for the same
reason the top of this page gives.

## Composition with PR #197

Measured on a throwaway merge of `pr-197` (`10d91848`) into this branch; no
branch carries it.

`git merge` reports **no conflict** — and the result **does not compile**. PR
#197 adds nine new `SheetController(...)` constructions to
`test/sheet/sheet_controller_test.dart`, and this PR makes `sessionPageUrl` a
**required** parameter of that constructor, so the merged file fails
`dart analyze` with nine `missing_required_argument` errors (lines 411, 452, 494,
540, 573, 595, 622, 662 and 702 of the merged file) and `flutter test` cannot
load it. Nothing under `lib/` conflicts: #197 touches `_loadRememberedMsisdn`,
`forgetRemembered`, `submitMsisdn` and the `CheckoutReadyRedirect` seeding, and
this PR touches `startRedirect` and the two URL builders.

The resolution is one line per site — `sessionPageUrl: _sessionPageUrl,` beside
each `client:` — and it belongs to whichever of the two merges **second**. Added
by hand on the throwaway merge, the merged tree is green: `dart analyze
--fatal-infos` clean, `flutter test` **314 passed, 0 failed**.

## What this does **not** prove

- **The leg end to end.** Nobody has driven a redirect rail from the sheet
  through a browser to the rail and back, on a device or against
  `just demo-up`. Every claim above is a unit- or component-level one.
- **The `sessionStorage` marker on a real in-app browser.** The mechanism is
  asserted in jsdom. Whether `SFSafariViewController` and Chrome Custom Tabs
  preserve it across the rail's cross-origin redirect is reasoned about in
  `src/lib/redirect-leg.ts`, not measured. Its failure mode is the duplicate
  screen returning, never a wrong outcome — the rail's `return_url` carries
  both `t` and `key` in its query (`vpay-db`'s `checkout_sessions.rs`), so a
  return page with no marker still has every credential it needs.
- **Anything in the Rust workspace.** `just ci`, `cargo nextest` and
  `just test-doc` were not run here. The Rust reading above is source reading,
  not a test run.
- **The auto-close path.** A suppressed return page renders no "return to the
  merchant" button, so the browser leg can no longer reach one of `stopUrls` by
  itself; the sheet resolves this rail on the dismissal signal alone. That is a
  consequence of the chosen design, not a defect, and D4's poll makes it
  correctness-complete — but it is unmeasured on every platform, exactly as
  `docs/status/mobile-flutter-plugin.md`'s lane-2 entry already says of that
  signal.
- **The skills.** `vpay-skills` is unchanged by this work and its
  `references/flutter-plugin.md` still describes only the pre-#192
  `VpayCheckout.start` window. The companion PR is owed; see
  [AGENTS.md](../../../AGENTS.md) § "Docs↔skills parity".
