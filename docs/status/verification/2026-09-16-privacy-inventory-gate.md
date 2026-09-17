# 2026-09-16 — the personal-data inventory and its gate (issue #144)

Adds the personal-data inventory, its machine-readable companion and the
**fourteenth** `just verify` gate. _(It was the thirteenth when this page was
written. `verify-versions` ([#201](https://github.com/vaam-apps/vpay/pull/201))
landed on `master` on 2026-09-17, from a branch this one had not seen, and this
branch merged it — so the two thirteenth gates met and the count is fourteen.
See the 2026-09-17 addendum at the foot of this page, which also corrects two
numbers below that were already a commit stale when this page shipped.)_

## What landed

- `schemas/privacy-inventory.yaml` — the machine-readable inventory: 25
  elements (16 personal-data), each carrying eight classification fields, six
  of which the gate checks are non-empty (ADR-0020 §1) and the copies (database columns) that share it, plus 10
  registered non-database surfaces.
- `docs/reference/personal-data-inventory.md` — the human-facing inventory,
  the element model, the personal-data columns and the non-database surfaces.
- `cargo xtask verify-privacy-inventory` — the gate. It derives the
  authoritative database column set by parsing `backends/migrations` (not
  `schemas/vpay.cstack`, which models less than the whole database) and fails
  in both directions: a migrated column with no element, and an element copy
  naming no live column. It also validates each element's six fields and the
  non-database-surface registry.
- Wired into `just verify` (fourteen gates after the 2026-09-17 merge; thirteen
  as delivered), CI's `self-checks` job,
  `AGENTS.md`, `CLAUDE.md`, `docs/status.md` and `docs/status/gates.md`.

## What the gate caught

The inventory started from a migration-derived column list that did not model
`DROP COLUMN` / `RENAME COLUMN`. The gate — once it parsed the final schema —
flagged every stale or missing row:

- `oauth_signing_keys.private_key_pem` / `.id` dropped or renamed to `kid` by
  migration 0010;
- `payment_intents.last_payment_error` dropped by migration 0014;
- `staff_members.{password_hash, totp_secret, password_change_required,
totp_enrolled_at, last_totp_step}` dropped by migration 0044 (moved to
  `credentials`).

All were corrected in the same commit. Three real SQL subtleties had to be
modelled for the parser to reflect the final schema at all:

1. **`ALTER TABLE ... DROP/RENAME COLUMN`** — the final schema, not the
   accumulated one.
2. **String-aware comment stripping** — 0007's
   `CHECK (private_key_pem LIKE '-----BEGIN%KEY-----%')` begins with `--`;
   a naive stripper eats the expression and leaves the `CHECK (` unclosed.
3. **Splitting `CREATE TABLE` bodies by top-level commas and skipping
   constraint lines**, so `CONSTRAINT`/`CHECK`/`PRIMARY KEY` lines do not read
   as columns.

## Evidence

- `cargo test -p xtask`: 259 passed, 0 ignored. Nine of them are
  `privacy_inventory_tests`, including a mutation per direction: adding a
  `phone` column to a migration with no element fails direction A; adding a
  `ghost` column to the inventory with no migration fails direction B; a
  duplicate surface id and a surface id colliding with an element name each
  fail; the `DROP`/`RENAME` handling and the string-aware comment stripper are
  pinned by their own tests.
- `cargo xtask verify-privacy-inventory`: ok — 303 database columns classified
  across 25 elements (16 personal-data, 17 necessary), checked in both
  directions against the 303 the migrations derive; 10 non-database surfaces
  registered (6 not yet statically enumerable).
- `cargo xtask verify-links`: ok — 1 669 links in 375 tracked markdown files.

## What this does not claim

- The six non-DB surfaces marked `enumerable: false` (logs, metrics, webhook
  payloads, provider rail, merchant API, backups) lack independent static
  scanners and are recorded as unmet criteria that keep #144 open — not faked.
- Every RFC-0002 D1–D13 policy decision stays open. The `retention` values are
  classes, not periods; the legal basis / controller-vs-processor questions
  are `unresolved`, not guessed.
- No full `just ci` was run on this branch (per the branch's standing
  instruction not to run concurrent local builds); the gates run here are the
  ones this change touches plus `verify-links`.

## 2026-09-17 — the review, and what two numbers above really were

**Two numbers on this page were already stale when it shipped**, and they are
corrected rather than rewritten, because a dated evidence page that quietly
agrees with its tree is the one thing this directory exists not to be:

- "`cargo test -p xtask`: **259** passed … **Nine** of them are
  `privacy_inventory_tests`" — the delivered branch had **263** passed, **0**
  ignored, of which **13** were `privacy_inventory_tests`. The page recorded a
  run from an earlier commit of the same branch. The pull request's own body
  says 263 and 13.
- "**303** database columns … against the **303** the migrations derive" — it
  is **295** on this tree. 303 is what the parser derived, and the parser was
  wrong in a way both directions of the gate agreed with; see below.

**What the review changed.** The SQL parser modelled `DROP COLUMN` but not
`DROP TABLE`. Migration `0009` drops `merchant_api_keys`, so its eight columns
stayed in the derived set and **both** directions of the gate agreed about a
table no database has — the inventory classified all eight, and
`docs/reference/personal-data-inventory.md` published two of them as stored
merchant credentials. `drop_table_targets` and a word boundary in
`is_constraint_line` fix it; three tests pin it; the eight rows are gone.

**Re-run on the merge of `origin/master` at `eb078020`, 2026-09-17, macOS,
`cratestack` 0.12.0 on `PATH`:**

- `cargo xtask verify-privacy-inventory`: ok — **295** database columns across
  25 elements (16 personal-data, 17 necessary), both directions against the 295
  the migrations derive; 10 non-database surfaces registered (6 not yet
  statically enumerable, 6 with an unmet note, 4 elements name a recipient).
- `cargo test -p xtask`: see the `just ci` page for this branch. The
  `privacy_inventory_tests` module is **16** cases.
- `cargo xtask verify-links`: see the same page.

**Two things this branch inherits red and does not fix**, both `master`'s at
`eb078020` and both reproduced locally here:

- `just verify-versions` (#201) fails. The release PR
  [#203](https://github.com/vaam-apps/vpay/pull/203) had release-please
  re-serialise `deploy/helm/vpay/Chart.yaml` and
  `sdks/flutter/vpay_checkout_flutter/pubspec.yaml`, which dropped every
  comment in them — including the `x-release-please-version` annotations the
  gate requires of every `extra-files` entry.
- `just fmt-check-web` (prettier) fails on `AGENTS.md`, `CHANGELOG.md` and
  those same two YAML files. `AGENTS.md`'s two offending lines are inside the
  § Releasing block #201 added (`*new*`/`*not*` where prettier wants `_new_`/
  `_not_`); `master`'s own copy fails the same check.

`master`'s CI run
[35275177452](https://github.com/vaam-apps/vpay/actions/runs/35275177452) is
red on both steps. No file behind either failure is touched by this change.
`git diff --name-only origin/master...HEAD | xargs pnpm exec prettier --check`
— every file this branch does touch — passes.

**What this addendum still does not claim.** Every unmet criterion listed on
2026-09-16 is still unmet, and the review added three more — five `redact`
columns nothing redacts, `jobs.last_error`'s classification, and ADR-0020 §1's
missing per-copy necessity/control. They are in
[../../reference/personal-data-inventory.md](../../reference/personal-data-inventory.md)
and they keep #144 open.
