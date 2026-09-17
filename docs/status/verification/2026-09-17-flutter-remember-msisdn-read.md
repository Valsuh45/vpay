# 2026-09-17 — Flutter sheet: "remember this number" read-back fixed (issue #194)

Issue #194 found the native sheet's page-memory **read** broken, by hand, on
an iPhone 17 Pro / iOS 26.5 against a real `just demo-up` stack. The evidence
was internally consistent and precise: tick "Mémoriser ce numéro sur cet
appareil", pay, let it settle to «Paiement reçu», cold-relaunch, pick MTN —
the number field was empty and the checkbox unticked, even though «Oublier ce
que cet appareil a mémorisé» rendered (which only happens when a stored record
exists). So: write worked, the existence check worked, "forget" worked, and
only reading the value back into the field was broken.

## Root cause

Two independent defects in the widget/controller wiring, neither in the store
(`remember_msisdn.dart`) itself — the 90-day TTL was already enforced on read,
and `VpayRememberedMsisdn.read` already returned the stored number for the
matching rail:

1. **Prefill was gated on a screen transition.** `_VpayCheckoutSheetState.
_onControllerChanged` only wrote `_msisdnController.text` inside the
   `screen != _lastAnnouncedScreen` branch, but `SheetController.defaultMsisdn`
   is populated _asynchronously_ (the store read is unawaited after the
   transition that shows the form). So the value always arrived _after_ the
   one chance to use it — the prefill branch was skipped and the field stayed
   empty.
2. **The checkbox never reflected saved state.** `rememberChecked` was only
   ever set by the payer's own tap; it was never seeded from the stored record,
   so a relaunch showed it unticked even though a record existed (the hosted
   page's own `setRemember(record !== null)`).

## The fix

- `checkout_sheet.dart`: the prefill is now applied on **every** controller
  change, not only on a transition, still guarded by `_msisdnManuallyEdited`
  and empty text (the `screens.tsx` "uncontrolled on purpose" rule: a payer
  editing a prefilled number is never overridden).
- `sheet_controller.dart`: `_loadRememberedMsisdn` now seeds `rememberChecked`
  from `hasRecord` (the web's `remember = record !== null`), and is also run
  for the redirect entry screen (`CheckoutReadyRedirect`) so the box and the
  "forget" affordance are offered there too — not just on the push form.
  `read` stays rail-scoped for the number; the _tick_ reflects any non-expired
  record, exactly as the web's does (see the review-pass bullet below).

A review pass tightened consistency with the hosted page:

- the box is seeded **once** per sheet, not on every entry — the web's
  `setRemember(record !== null)` also runs once at startup — so a payer who
  unticks and moves between rails keeps it unticked rather than having it
  forced back on;
- `forgetRemembered` now unticks the box, matching the web's
  `onForget -> setRemember(false)` (a forgotten record with a still-ticked box
  could never happen on the web);
- a stale number loaded for a _previous_ rail is cleared before the async read
  for the new rail answers, so switching rails never shows the wrong number in
  the new rail's form even for a frame;
- the box seed is the **non-expired** half of the store
  (`VpayRememberedMsisdn.hasActiveRecord`): an expired record is something to
  forget (the button still shows) but nothing the box can truthfully say the
  device still remembers — `memory.ts`'s `parseMemoryRecord` returns `null`
  for an expired record, so the web's box is unticked for one too;
- an **unticked submit now clears** the record, not just a ticked one writing:
  `submitMsisdn` calls `forget` when `rememberChecked` is false, matching
  `checkout-client.tsx`'s `rememberOnSubmit -> pageMemory.clear()`. Without
  this, a payer who unticks and pays would still get the number back on the
  next relaunch — the very read-back #194 is about. The clear is guarded by
  `_rememberSeeded`: it cannot run before the async box-seed has landed, so a
  payer who submits into the tiny pre-seed window never has a record they did
  not untick cleared for them.

## Evidence

On Flutter 3.47.2 / Dart 3.13.2 (the `flutter-toolchain.toml` pin):

- `flutter test` (the full suite) → **305 passed / 0 skipped**. Two widget
  tests reproduce issue #194 exactly — the single-rail cold relaunch and the
  rail-picker → choose MTN path — asserting the number returns to the field
  **and** the box is ticked; controller tests pin `defaultMsisdn`/
  `hasRememberedRecord`/`rememberChecked` for the push, redirect, empty and
  expired-record cases, the untick-survives-rail-switch and forget-unticks
  behaviours, and the untick-clears-on-submit rule above (plus a store-level
  `hasActiveRecord` test).
- `dart analyze --fatal-infos` → no issues.

The 305 figure is the full suite on the merged base — re-measured after this
branch was rebased onto #196 (issue #193's deployment self-description), whose
own tests are counted in it; the #194 tests themselves are unchanged and green.

Not affected by this change: the payment path itself (the same walk that found
the bug settled to `paid` in the merchant DB), the write side, the "forget"
affordance, the 90-day TTL (already on read), and the deliberately-unwritten
redirect-rail "remember" persistence (still named in
`docs/flows/mobile-checkout.md` and `mobile-flutter-plugin.md` as not done) —
this change makes the redirect box _seed and read_ state, but it remains
display-only there: `startRedirect` still persists nothing, a known,
documented limitation.
The rail picker is still shown on relaunch rather than jumping to the
remembered rail — a deliberate match for the hosted page, which also shows the
picker (with a "last used" badge), not an auto-selection side effect.
