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

| Piece | State |
| --- | --- |
| `cargo xtask verify-sdk-parity` reads Dart | ✅ `dart_test_names` collects `test('…')`/`testWidgets('…')`/`group('…')` titles, single- and double-quoted, with escapes and raw (`r'…'`) strings; `PARITY_SKIPPED_DIRS` grew `.dart_tool` and `build`. Proven against a synthetic fixture tree in `.xtask/src/main.rs`'s `sdk_parity_tests` module — **not** against this repository's own `sdks/`, which has no Dart column yet. |
| The skip property, the one this gate exists for | ✅ `test('x', skip: true)` and a string `skip:` reason are **not** collected, mirroring `rust_test_names`' drop of `#[ignore]`d tests and `ts_test_names`' drop of `it.skip(…)`. Proven by mutation: `dart_decisive_mutation_a_live_test_passes_verify_sdk_parity` calls `verify_sdk_parity` on a synthetic tree and gets `Ok(())`; the same fixture with `skip: true` added (`dart_decisive_mutation_skip_true_fails_verify_sdk_parity_naming_the_cell`) gets `Err` naming both the cell and the SDK column. See the dated verification page below for the literal before/after. |
| `just install-flutter` / `analyze-flutter` / `test-flutter` | ✅ exist, each refuses with a named, human-readable reason — not a stack trace — when `sdks/flutter/vpay_checkout_flutter/` does not exist (true on this branch) or when the `flutter` SDK is not on `PATH`. **Not in `just ci` or `just verify`** (D-M3): confirmed by reading both recipe lists; neither names any of the three. |
| `flutter-toolchain.toml` | ✅ pins Flutter `3.47.2` / Dart `3.13.2` — the version installed on the host this lane was authored and verified against, not a floor computed from a `pubspec.yaml` (there is none yet). The file's own comment records that the host reports channel `[user-branch]`, not a clean channel pin the way `rust-toolchain.toml`'s `channel` is, and says the maintainer may want to fix that before this ships in an image. |
| ADR-0021 | ✅ [docs/adr/0021-flutter-checkout-plugin.md](../adr/0021-flutter-checkout-plugin.md) — records D1–D9 and D-M1–D-M6 as accepted. |
| `docs/flows/mobile-checkout.md` | ✅ the flow doc, carrying D9's Apple 3.1.3(e) and 3.1.1 quotes verbatim (not paraphrased) as a constraint on adoption, and naming — rather than deciding — the one open documentation-structure question against `hosted-checkout/page-memory-and-protocols.md`'s popup table. |

## What is not real yet, and whose it is to build

- **No Dart file exists in this repository.** `sdks/flutter/vpay_checkout_flutter/`
  does not exist on `claude/flutter-lane-b-gate`; Lane A of the brief creates
  it (`lib/`, `pigeons/checkout.dart`, `test/`, `example/`).
- **No platform host exists.** No `android/`, `ios/`, `macos/` directory, no
  Android `Activity`, no `WKWebView` controller. Lane C, after Lane A.
- **The plugin's own parity table.** `docs/sdks/parity.md` gains a third
  table under Lane A's ownership — Lane B does not touch that file. **The
  dated ⛔ row that the plugin's tests are not run by `just ci` is owed there,
  by Lane A** — this page does not carry it, because the row belongs next to
  the table it qualifies, not on a status page describing the gate that would
  read it.
- **`docs/status.md`'s gate table is unchanged.** It lists what `just verify`
  refuses (twelve gates); Flutter's recipes are not one of them and this page
  does not claim otherwise. Nothing on `docs/status.md` itself was touched by
  this lane.
- **No CI gate, no device, no real rail, no store review.** Every payment this
  plugin will ever complete, once Lane A and Lane C land, will settle against
  WireMock — exactly like every other payment in this repository's history —
  until stated otherwise with evidence.

## Verification

- [verification/2026-09-13-flutter-lane-b-gate.md](verification/2026-09-13-flutter-lane-b-gate.md)
  — this lane's `cargo test -p xtask`, `cargo clippy --all-targets`,
  `just verify-links` and `just verify-sdk-parity` runs, and the literal
  before/after of the decisive skip mutation.
