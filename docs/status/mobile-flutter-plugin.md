# Mobile Flutter plugin (`vpay_checkout_flutter`)

New page, 2026-09-13. Not a merchant SDK — a payer surface, like
`@vaam-apps/vpay-stripe-js` — so it is not folded into
[merchant-sdks.md](merchant-sdks.md). See
[docs/flows/mobile-checkout.md](../flows/mobile-checkout.md) for the process
and [ADR-0021](../adr/0021-flutter-checkout-plugin.md) for the decisions.

## What is real today

Built by Lane B of
[`docs/plans/2026-09-13-flutter-plugin-brief.md`](../plans/2026-09-13-flutter-plugin-brief.md),
on `claude/flutter-lane-b-gate`:

| Piece                                                       | State                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cargo xtask verify-sdk-parity` reads Dart                  | ✅ `dart_test_names` collects `test('…')`/`testWidgets('…')`/`group('…')` titles, single- and double-quoted, with escapes and raw (`r'…'`) strings; `PARITY_SKIPPED_DIRS` grew `.dart_tool` and `build`. Proven against a synthetic fixture tree in `.xtask/src/main.rs`'s `sdk_parity_tests` module — **not** against this repository's own `sdks/`, which has no Dart column yet.                                                                                                                                                                                               |
| The skip property, the one this gate exists for             | ✅ `test('x', skip: true)` and a string `skip:` reason are **not** collected, mirroring `rust_test_names`' drop of `#[ignore]`d tests and `ts_test_names`' drop of `it.skip(…)`. Proven by mutation: `dart_decisive_mutation_a_live_test_passes_verify_sdk_parity` calls `verify_sdk_parity` on a synthetic tree and gets `Ok(())`; the same fixture with `skip: true` added (`dart_decisive_mutation_skip_true_fails_verify_sdk_parity_naming_the_cell`) gets `Err` naming both the cell and the SDK column. See the dated verification page below for the literal before/after. |
| `just install-flutter` / `analyze-flutter` / `test-flutter` | ✅ exist, each refuses with a named, human-readable reason — not a stack trace — when `sdks/flutter/vpay_checkout_flutter/` does not exist (true on this branch) or when the `flutter` SDK is not on `PATH`. **Not in `just ci` or `just verify`** (D-M3): confirmed by reading both recipe lists; neither names any of the three.                                                                                                                                                                                                                                                |
| `flutter-toolchain.toml`                                    | ✅ pins Flutter `3.47.2` / Dart `3.13.2` — the version installed on the host this lane was authored and verified against, not a floor computed from a `pubspec.yaml` (there is none yet). The file's own comment records that the host reports channel `[user-branch]`, not a clean channel pin the way `rust-toolchain.toml`'s `channel` is, and says the maintainer may want to fix that before this ships in an image.                                                                                                                                                         |
| ADR-0021                                                    | ✅ [docs/adr/0021-flutter-checkout-plugin.md](../adr/0021-flutter-checkout-plugin.md) — records D1–D9 and D-M1–D-M6 as accepted.                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `docs/flows/mobile-checkout.md`                             | ✅ the flow doc, carrying D9's Apple 3.1.3(e) and 3.1.1 quotes verbatim (not paraphrased) as a constraint on adoption, and naming — rather than deciding — the one open documentation-structure question against `hosted-checkout/page-memory-and-protocols.md`'s popup table.                                                                                                                                                                                                                                                                                                    |

## What Lanes A and C added, and the 2026-09-14 review

Lane B's table above described the gate and the docs. The plugin itself
landed afterwards, and until 2026-09-14 this page still said "No Dart file
exists in this repository" — true when Lane B wrote it, false from Lane A's
merge onward. Corrected here by the review.

| Piece                                   | State                                                                                                                                                                                                                                                                                                 |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The Dart core (`lib/`)                  | ✅ browser client, pure state machine, result/error types, redaction, the pigeon seam. `flutter test` green; counts and skips on the dated verification page.                                                                                                                                         |
| The Android host                        | ✅ exists and **compiles**: `flutter build apk --debug` on `example/`, and the merged manifest carries `VpayCheckoutActivity` with `android:exported="false"`. `onReceivedSslError` is not overridden and there is no `addJavascriptInterface` call. No device, no emulator, no instrumentation test. |
| The web host                            | ✅ exists and **compiles**: `flutter build web` on `example/`, and Flutter's generated `web_plugin_registrant.dart` calls `WebVpayCheckoutPlatform.registerWith`. No browser has driven the popup.                                                                                                    |
| iOS and macOS hosts                     | ⛔ the Swift exists and is **compiled by nobody** — Linux host, no `xcodebuild`, reviewed by reading only.                                                                                                                                                                                            |
| `VpayCheckoutMode.externalBrowser` (D8) | ⛔ designed, not built. Until 2026-09-14 the parameter was accepted and silently ignored — the caller got the in-app WebView. It now throws `UnimplementedError`.                                                                                                                                     |
| The parity table                        | ✅ `docs/sdks/parity.md`'s third table, 550 proving tests across the file, every Flutter ✅ cell naming a Dart test that actually ran.                                                                                                                                                                |

### What the review found and fixed

Each was measured by mutation; the before/after exit codes are on the dated
page below.

1. **`externalBrowser` was silently ignored** — the public API accepted a
   mode it did not have and handed back the in-app WebView.
2. **The pigeon-generated `toString` rendered the session secret.**
   `ShowCheckoutRequest.url`'s fragment _is_ the session `client_secret`, and
   the generated Dart, Kotlin and Swift all interpolated it. The design doc
   predicted this by name ("generated code is how this regresses") and the
   D6 parity row was ✅ with no test over that file.
3. **`no_logging_test.dart` excluded member calls**, so
   `developer.log(secret)` in `lib/` passed it.
4. **The gate's Dart reader collected tests that never run** — a skipped
   group's tests, commented-out declarations, and titles quoted in strings.
5. **The window's one event could be dropped**, hanging `start()` forever,
   because the broadcast stream was subscribed only after `show()` returned.
6. **A malformed 200 escaped as a bare `TypeError`** out of a poll, against
   this package's own stated contract.
7. **`allowInsecureUrl` was hard-coded `false`** and never reached the host.

## What is still not real

- **No `just ci` gate** (D-M3). `install-flutter`/`analyze-flutter`/
  `test-flutter` exist; none is in `just ci` or `just verify`, and
  `docs/status.md`'s gate table does not claim otherwise. Every count this
  repository quotes for this package is a human running it by hand.
- **No iOS or macOS compile.** Not "not yet run" — there is no toolchain on
  this host and there cannot be.
- **No device, no emulator, no browser.** Android is proven by compiling and
  web by compiling; neither has been opened.
- **No real rail, and no running vpay.** Every server in this package's suite
  is `MockClient`. Nothing here has been driven against `compose.demo.yml`.
- **No App Store or Play review.** ADR-0021 and D9 read the published rules;
  a reviewer's verdict is a different thing this repository will not have.
- **The Android 21 / iOS 12 floor is a claim nobody will test.**
- **No desktop Linux or Windows.**

## Verification

- [verification/2026-09-13-flutter-lane-b-gate.md](verification/2026-09-13-flutter-lane-b-gate.md)
  — Lane B's `cargo test -p xtask`, `cargo clippy --all-targets`,
  `just verify-links` and `just verify-sdk-parity` runs, and the literal
  before/after of the decisive skip mutation.
- [verification/2026-09-14-flutter-review.md](verification/2026-09-14-flutter-review.md)
  — the review's gate output on the merged head, and every mutation it
  measured, with the exit code read from a file in each case.
