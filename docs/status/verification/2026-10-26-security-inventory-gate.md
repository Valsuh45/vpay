# `verify-security-inventory`, the sixteenth gate (issue #150, ADR-0033)

Measured on 2026-10-26 on the review branch for
[PR #356](https://github.com/vaam-apps/vpay/pull/356), against the tree that
addresses the review of 2026-10-24.

## What changed

- `schemas/security-inventory.yaml` was rewritten to match the code: the five
  trust tiers, the worker's real job kinds, the five `authkestra` tables, the
  corrected `vpay-config` paths, the real callback routes, the two published
  packages, the shipped CI jobs, and honest `gap`/`partial` statuses.
- `cargo xtask verify-security-inventory` now deserializes the whole inventory
  with `deny_unknown_fields`, checks both directions of the table set, checks
  every cited path and test name, validates secret `config_keys` against a
  closed set, and refuses a gap whose issue number no document cites.
- The gate is gate 16 of `just verify` and a step in CI's `self-checks` job.
  Both `count:verify-gates` tallies and every current prose count moved from
  fifteen to sixteen.
- `docs/security/trust-boundaries.md`, `docs/security/data-flows.md`,
  `docs/security/README.md`, `docs/reference/security-asset-inventory.md` and
  ADR-0033 were corrected to describe what exists, not what the first draft
  hoped existed.

## Gate output

```text
$ cargo xtask verify-security-inventory
verify-security-inventory: ok — 5 service(s), 4 state store(s), 33 table(s),
11 secret class(es), 15 material control(s) and 7 tracked gap(s) verified in
schemas/security-inventory.yaml
```

## Failing cases

`cargo test -p xtask test_security_inventory` runs twelve cases. The real
inventory passes and eleven mutations fail:

| Mutation                                        | Assertion                           |
| :---------------------------------------------- | :---------------------------------- |
| Missing inventory                               | `the inventory is mandatory`        |
| Misspelt `tables:` key                          | `deny_unknown_fields` refuses it    |
| A table no migration creates                    | `ghost` is named                    |
| A live table in no state store                  | `jobs` is named                     |
| `rails.mtn_momo.api_key` as a config key        | the invented path is named          |
| A nonexistent implementation path               | `nope.rs` is named                  |
| A cited test no source declares                 | the test name is named              |
| A gap issue no document cites                   | `999999` is named                   |
| An issue number that is a prefix of a cited one | `#5` is refused against `issues/56` |
| A `gap` control with no `related_gap`           | `related_gap` is named              |
| A published manifest with `private: true`       | the manifest is refused             |

## Gate and doc checks

```text
$ cargo test -p xtask test_security_inventory
12 passed; 0 failed

$ cargo xtask verify-doc-counts
13 documented count(s) in 11 of 300 markdown file(s) agree

$ cargo fmt --all -- --check
clean
```

## `just verify`

```text
$ just verify
verify-no-mocks: ok — no test double reachable from a shipping binary
verify-status: ok — 2 unimplemented item(s), all declared in docs/status.md
verify-errors: ok — 20 error type(s), all classified; anyhow confined to binaries
verify-sdk-parity: ok — 792 proving test(s), 46 dated gap(s), 35 SDK method(s)
verify-links: ok — 2858 repository link(s) in 501 tracked markdown file(s)
verify-npm-scope: ok — 3 publishable package(s) under sdks/
check-schema: ok — schemas/vpay.cstack type-checks under cratestack 0.12.0
               (the local CLI is 0.12.0; this repository pins 0.15.0, and the
               recipe says so before it runs)
verify-serde: ok — 130 serialisable type(s), 17 exempted with a reason
verify-repositories: ok — 4 concrete implementation(s), named by none of 99 files
verify-toolchain: ok — rust-toolchain.toml pins 1.98.0
verify-migrations: ok — 53 migration file(s) match MANIFEST.sha256
verify-versions: ok — 26 version references all say 0.11.0
verify-privacy-inventory: ok — 323 columns, 26 elements, 36 debug_protections
verify-doc-counts: ok — 13 documented count(s) in 11 of 300 markdown files
verify-security-inventory: ok — 5 services, 4 state store(s), 33 tables,
                            11 secret classes, 15 controls, 7 tracked gaps
verify: ok — the sixteen gates above passed; the verify-docs report is advisory
```

## `just ci`

`just ci` is not green on this head, and neither failure is caused by this
change. The steps were run individually so each outcome is attributable:

```text
$ just fmt-check                      clean
$ cargo clippy --workspace --all-targets -- -D warnings   clean
$ just verify                         16 gates green (above)
$ just test-doc                       5 passed, 0 failed
$ just verify-ignored                 0 ignored (expected 0), 54 binaries, 2447 total
$ just lint-web                       clean
$ just audit-web                      no moderate, high or critical advisory
$ just deny                           FAILED: RUSTSEC-2026-0387 (crypto-bigint 0.5.5)
                                      and RUSTSEC-2026-0386 (tokio 1.53.1)
$ just test-web                       FAILED: 3 timeouts in
                                      payments-filters.test.tsx
$ cargo nextest run --workspace       stopped at 2061/2446 with 0 failures
                                      (container-backed suite, >35 min on this host)
```

The `deny` findings are dependency advisories on the branch's base
(`14fc6241`), not on any crate this change touches; `cargo deny` reaches them
through `testcontainers`/`tokio` and `rsa`/`crypto-bigint`. `test-web`'s three
timeouts are the dashboard's `payments-filters.test.tsx` under the
workspace-wide parallel run; the same file passes alone (**12 of 12**) and the
failure is a 5-second test timeout, not an assertion. Neither file is changed
by this PR.

`cargo nextest` was not run to completion, so this page does not claim it.
Every test it had reached passed, and the gate this change adds is exercised by
`cargo test -p xtask test_security_inventory` above.

## What the gate does not check

It does not call GitHub, so a tracked issue is checked only by format and by
being cited under `docs/`; `verify-citations` remains the network check. It
does not judge whether a control's evidence is sufficient, and it does not run
the tests it cites. Those stay review questions.
