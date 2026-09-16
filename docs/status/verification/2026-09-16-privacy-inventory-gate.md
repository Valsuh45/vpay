# 2026-09-16 — the personal-data inventory and its gate (issue #144)

Adds the personal-data inventory, its machine-readable companion and the
thirteenth `just verify` gate.

## What landed

- `schemas/privacy-inventory.yaml` — the machine-readable inventory: 25
  elements (16 personal-data), each carrying the six-field ADR-0020 §1
  classification and the copies (database columns) that share it, plus 10
  registered non-database surfaces.
- `docs/reference/personal-data-inventory.md` — the human-facing inventory,
  the element model, the personal-data columns and the non-database surfaces.
- `cargo xtask verify-privacy-inventory` — the gate. It derives the
  authoritative database column set by parsing `backends/migrations` (not
  `schemas/vpay.cstack`, which models less than the whole database) and fails
  in both directions: a migrated column with no element, and an element copy
  naming no live column. It also validates each element's six fields and the
  non-database-surface registry.
- Wired into `just verify` (now thirteen gates), CI's `self-checks` job,
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
