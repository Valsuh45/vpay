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
- `cargo test -p xtask`: **266 passed, 0 ignored**, of which **16** were
  `privacy_inventory_tests`. _(This read "see the `just ci` page for this
  branch" until 2026-09-18, and there was no such page. The number is recorded
  here now rather than pointed at, and it is **266**, not the 263 the bullet
  above quotes: 263 was the delivered branch before the merge, and merging
  `master` brought three more xtask cases with `verify-versions`. The
  2026-09-18 section below re-measures both on the head of this branch.)_
- `cargo xtask verify-links`: ok — 1 718 links in 399 tracked markdown files.

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
~~`git diff --name-only origin/master...HEAD | xargs pnpm exec prettier
--check` — every file this branch does touch — passes.~~ **Struck 2026-09-18:
that was not true when it was written.** `AGENTS.md` is a file this branch
touches **and** one of the four that recipe fails on, so the command reports
it. What is true, and is what the sentence meant, is that `AGENTS.md` fails on
`master`'s two lines and on no line this branch wrote — established by
formatting both copies and diffing them, in the 2026-09-18 section below.
Every other file this branch touches passes.

**What this addendum still does not claim.** Every unmet criterion listed on
2026-09-16 is still unmet, and the review added three more — five `redact`
columns nothing redacts, `jobs.last_error`'s classification, and ADR-0020 §1's
missing per-copy necessity/control. They are in
[../../reference/personal-data-inventory.md](../../reference/personal-data-inventory.md)
and they keep #144 open.

## 2026-09-18 — the review's second pass, and the `just ci` this page owed

The 2026-09-16 section ends "**No full `just ci` was run** on this branch", and
the pull request body says the same. It has now been run, on the merge of
`origin/master` at `eb078020`, macOS 25.6.0, cargo 1.98.0, `cratestack` 0.12.0
on `PATH`. `just ci` stops at its first failing recipe and the first one it
reaches is `fmt-check-web` — `master`'s failure, not this branch's — so every
step was run separately, in `just ci`'s own order, and every one is below with
what it printed.

### What the pass changed in the gate

`verify-privacy-inventory` derived its authoritative column set with
`stmt.to_uppercase().find("CREATE TABLE")`. Four defects, each measured by
driving `migrations_db_columns` over temp trees, each failing **open** with the
gate green:

1. **One literal space.** `CREATE  TABLE t (…)` with two spaces,
   `CREATE<TAB>TABLE`, or a `CREATE` left at the end of a wrapped line derived
   **nothing at all** — the whole table, every column of it, invisible to both
   directions. `ALTER  TABLE t ADD COLUMN email` lost `email`. `DROP  TABLE t`
   left `t` standing, re-opening through a second space the `0009` hole the
   2026-09-17 pass had just closed. `RENAME  COLUMN a TO b` left the old name
   live. Nothing in this repository reformats SQL: the only thing keeping the
   gate correct was that all 48 migrations happen to be typed with one space.
2. **No word boundary** (`RECREATE TABLE` contains `CREATE TABLE`) and **no
   string-literal awareness** — in a repository whose `COMMENT ON` bodies are
   essays about migrations, so one containing the words `DROP TABLE customers`
   would have removed the real table from the derived set.
3. **Offsets taken from an uppercased copy indexed the original.**
   `str::to_uppercase` is not length-preserving for every input.
4. **`strip_sql_comments` pushed `byte as char`**, re-encoding each byte of a
   multi-byte character as its own Latin-1 code point. These migrations are full
   of `§`, `—` and `±`, so its output was mojibake **and longer than the input**
   while its own doc comment claimed length was preserved. Nothing indexed back
   into the source, so nothing misparsed: the false claim was the defect.

`kw_end`/`words_at` replace the matching — in order, ASCII-case-insensitive,
whitespace-tolerant, boundary-anchored, string-aware, on the bytes of the
statement itself. **And the forms the parser cannot read are now refused rather
than skipped.** `CREATE TABLE … AS SELECT`, `… PARTITION OF …`,
`… INHERITS (…)`, a `(LIKE …)` body and `ALTER TABLE … RENAME TO` each derived
an empty table and **passed**; each now fails the gate by name. The 2026-09-16
page had named three of the five as unmodelled and left them as an observation,
which is not a gate. Ten new cases pin all of it
(`privacy_inventory_tests` 16 → **26**), none of them touching a shipped
migration, because `verify-migrations` checksums those.

The gate derives **the same 295 columns across 25 elements** before and after,
which is what a hardening pass should do.

### What the pass would not decide

Ten `subject: payer|staff|merchant` columns and ten `subject: none|system`
columns were read against the migration that defines each. No fabricated
compliance claim, no invented lawful basis, no retention period stated as a
commitment; every RFC-0002 D1–D13 answer is still open, and the six
`enumerable: false` surfaces are still rendered as unmet criteria everywhere
they appear. Two outright false statements on
[../../reference/personal-data-inventory.md](../../reference/personal-data-inventory.md)
were fixed, because they were claims and not judgements: its field table listed
four `subject` values where the gate enforces five, and it credited
`provider_requests.error_kind` with "a closed operator-label vocabulary" that
`0016_create-provider-requests.sql:32-36` says does not exist ("Free text on
purpose"). **Six classifications the migrations' own comments contradict were
recorded, not changed**, in that page's § "Classifications the review could not
settle" — each needs an element split or an RFC-0002 D1 answer, and quietly
re-deciding a GDPR artifact in a review pass is what this directory exists to
prevent.

### Evidence, in `just ci`'s order

| Step                         | Result                                                                                                                                                                                                                                               |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `just fmt-check-rust`        | **ok** — `cargo fmt --all -- --check`, exit 0                                                                                                                                                                                                        |
| `just fmt-check-web`         | **FAILS** — `master`'s, see below                                                                                                                                                                                                                    |
| `just clippy`                | **ok**, exit 0                                                                                                                                                                                                                                       |
| `just verify`                | **stops at `verify-versions`**, the thirteenth gate — `master`'s, see below. The twelve before it are below; the two after it were run separately                                                                                                    |
| ‣ `verify-no-mocks`          | ok — no test double reachable from a shipping binary                                                                                                                                                                                                 |
| ‣ `verify-status`            | ok — 1 unimplemented item, declared and still in shipping code                                                                                                                                                                                       |
| ‣ `verify-errors`            | ok — 20 error types, all classified; 17 `#[from]` variants delegate                                                                                                                                                                                  |
| ‣ `verify-sdk-parity`        | ok — 661 proving tests, 37 dated gaps, 35 methods, 39 rows                                                                                                                                                                                           |
| ‣ `verify-links`             | ok — **1 723** links in 399 tracked markdown files                                                                                                                                                                                                   |
| ‣ `verify-npm-scope`         | ok — 2 publishable packages, 1 private                                                                                                                                                                                                               |
| ‣ `check-schema`             | ok — 27 declarations, `cratestack` **0.12.0**, the version `justfile` pins                                                                                                                                                                           |
| ‣ `verify-serde`             | ok — 102 types, 17 exemptions                                                                                                                                                                                                                        |
| ‣ `verify-repositories`      | ok — 4 implementations, 84 source files outside `vpay-db`                                                                                                                                                                                            |
| ‣ `verify-toolchain`         | ok — 1.98.0, matching the one `FROM rust:` in `backends/Dockerfile`                                                                                                                                                                                  |
| ‣ `verify-ui`                | ok — silent on success, exit 0 only                                                                                                                                                                                                                  |
| ‣ `verify-migrations`        | ok — 48 files match `MANIFEST.sha256`                                                                                                                                                                                                                |
| ‣ `verify-privacy-inventory` | ok — **295** columns across **25** elements (16 personal-data, 17 necessary), both directions against the 295 the migrations derive; **10** non-database surfaces (6 not statically enumerable, 6 with an unmet note, 4 elements naming a recipient) |
| ‣ `verify-docs`              | the advisory report, exit 0                                                                                                                                                                                                                          |
| `just test-rust`             | **2 015 run, 2 011 passed, 4 failed, 0 skipped** — the four are macOS-only and pre-existing, see below                                                                                                                                               |
| `cargo test -p xtask`        | **276 passed, 0 failed, 0 ignored**, of which **26** are `privacy_inventory_tests`                                                                                                                                                                   |
| `just test-doc`              | **121 passed, 1 ignored** across 14 crates — a separate runner from `nextest`, which runs no doctest                                                                                                                                                 |
| `just verify-ignored`        | ok — 0 ignored (expected 0), 48 test binaries (expected 48), 2 015 total (minimum 1 080)                                                                                                                                                             |
| `just lint-web`              | **ok**, exit 0                                                                                                                                                                                                                                       |
| `just test-web`              | **ok**, exit 0                                                                                                                                                                                                                                       |
| `just audit-web`             | ok — no moderate, high or critical advisory in the workspace                                                                                                                                                                                         |
| `just deny`                  | ok — advisories ok, bans ok, licenses ok, sources ok                                                                                                                                                                                                 |
| `just docs-check-citations`  | **FAILS** on one pre-existing dangling id — see below. Not part of `just ci`; it needs the network                                                                                                                                                   |

### Four Rust failures that are this machine, not this branch

`backends/` is untouched by this branch — `git diff --stat origin/master...HEAD
-- backends/` is empty — and all four failures are in
`backends/tests/integration/tests/staff_sign_in.rs`:
`a_forwarded_for_header_from_an_untrusted_peer_buys_no_fresh_budget`,
`the_second_factor_is_rate_limited_and_not_only_the_password`,
`the_sign_in_rate_limit_is_per_source_address` and
`two_replicas_share_one_sign_in_budget`. Each ends:

```
  1: client error (Connect)
  2: tcp bind local error
  3: Can't assign requested address (os error 49)
```

They simulate distinct client source addresses with
`reqwest::ClientBuilder::local_address` — `staff_sign_in.rs:1496`, `:1601`
(`127.0.0.4`), `:1760` (`127.0.0.20`), `:2110` (`127.0.0.30 + n`). **Linux
assigns the whole `127.0.0.0/8` to `lo`, macOS assigns only `127.0.0.1` to
`lo0`** (`ifconfig lo0` on this host shows exactly one `inet`), so the bind
returns `EADDRNOTAVAIL`. They fail identically alone
(`cargo nextest run -p vpay-tests-integration --test staff_sign_in
--no-fail-fast`: 27 run, 23 passed, the same 4 failed), so this is a platform
fact and not a load effect, and it is why CI is green on them. A
`sudo ifconfig lo0 alias 127.0.0.N up` per address is the local fix; nothing
here changes the tests.

_(Two other tests failed once each, earlier in the day, on runs taken while
other suites were building on the same host —
`checkout_sessions::the_housekeeping_sweep_expires_a_stale_session_and_spares_a_paying_one`
and `adapter_conformance::not_found_is_never_on_its_own_a_failure::case_2_orange_money`.
Both passed in isolation and both passed in the clean run above. They are
recorded because a number on this page should say what was seen, not the best
of three.)_

### The three failures this branch inherits and does not fix

`master`'s own CI run
[35275177452](https://github.com/vaam-apps/vpay/actions/runs/35275177452) at
`eb078020` fails on exactly the first two — queried rather than assumed:
`self-checks (no-mocks, status)` fails at
`verify-versions (release-please's bump is complete)`, and `web` fails at
`fmt-check-web (prettier --check)`.

```
$ just verify-versions
xtask: release version references disagree, or a release-please annotation is missing:
  deploy/helm/vpay/Chart.yaml: listed in release-please-config.json's extra-files but carries no x-release-please-version line, so release-please will never change it
  sdks/flutter/vpay_checkout_flutter/pubspec.yaml: listed in release-please-config.json's extra-files but carries no x-release-please-version line, so release-please will never change it
```

```
$ just fmt-check-web
[warn] AGENTS.md
[warn] CHANGELOG.md
[warn] deploy/helm/vpay/Chart.yaml
[warn] sdks/flutter/vpay_checkout_flutter/pubspec.yaml
```

`AGENTS.md` is the only one of those four this branch edits, and its failure is
**byte-identical to `master`'s**: prettier wants `_new_`/`_not_` where the
§ Releasing block #201 added writes `*new*`/`*not*` — `master`'s lines 397 and
409, this branch's 416 and 428, the same two lines displaced by insertions
above them. Established by formatting both copies and diffing the results, not
by reading. Every other file this branch touches passes
`pnpm exec prettier --check`.

The third is **not** in `just ci` and so is not in that CI run either:

```
$ just docs-check-citations
xtask: 1 cited id(s) do not exist in vaam-apps/vpay. …
  - run 46733123454 does not exist (HTTP 404), cited at docs/runbooks/live-sandbox-test.md:173, docs/runbooks/live-sandbox-test.md:231, docs/status/verification/2026-09-15.md:18
```

All three cited lines are on `master` unchanged and none of the three files is
touched here. This page's own new citation — run `35275177452`, 6 citations —
resolves.
