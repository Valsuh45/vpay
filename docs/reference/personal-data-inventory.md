# Personal-data inventory

_Issue [#144](https://github.com/vaam-apps/vpay/issues/144). The machine-readable
companion is [`schemas/privacy-inventory.yaml`](../../schemas/privacy-inventory.yaml);
this page is the human-facing version. The architecture is
[ADR-0020](../adr/0020-privacy-controls-and-evidence.md); the unresolved policy
decisions (legal basis, roles, retention periods) are
[RFC-0002](../rfc/0002-gdpr-policy-and-operator-decisions.md)'s D1–D13 and
[open-decisions.md](../open-decisions.md)._

## What this is

An inventory of every personal-data processing surface vpay owns: every
database column across the authoritative schema, and every non-database surface
(logs, metrics, traces, events, webhooks, the payer's browser, the rails,
the merchant API, the observability listener, backups).

It is **not** a legal document. It classifies _what the product stores,
derives, logs, emits and sends_, so that the engineering controls (erasure,
retention, minimisation, export, incident evidence) can be built on a shared,
code-grounded map. Controller/processor roles, lawful bases, notices, retention
**periods** and disclosure approval are human decisions and are recorded here as
`unresolved` rather than guessed — RFC-0002 keeps each one open with a named
owner.

## How it is checked

`cargo xtask verify-privacy-inventory` (a gate in `just verify`) reads
`schemas/privacy-inventory.yaml` and derives the authoritative database column
set by parsing `backends/migrations` (the source of truth — `schemas/vpay.cstack`
deliberately models less than the whole database). It fails in **both**
directions, exactly like `verify-status`:

- a migrated column with no element in the inventory → fail;
- an inventory element copy naming no live column → fail.

So a new privacy-relevant column cannot land silently, and a stale inventory
row cannot survive the column it named. The gate also validates every element's
six fields and every registered non-database surface.

## The element model

Each entry in the inventory is a **data element**: a stable identifier shared by
every copy of one piece of data (ADR-0020 §1). Each element carries the
six-field classification and a `copies` list of the database columns (and, once
the non-DB registry is complete, the non-database surfaces) that hold it:

| Field            | Meaning                                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------------ |
| `subject`        | data-subject category: `payer`, `staff`, `merchant`, or `none` (system/technical)                                  |
| `purpose`        | the product purpose for which the value is processed                                                               |
| `necessary`      | whether the value is required for that purpose to function                                                        |
| `tenant_boundary`| `merchant` or `system` — which boundary the value is scoped to                                                     |
| `recipients`     | third parties that receive it (e.g. `mtn_momo`, `orange_money`, `merchant-endpoint`)                               |
| `retention`      | the retention **class** (not the period — the period is an RFC-0002 decision)                                      |
| `owner`          | the accountable retention owner (`maintainer`, `operator`, `merchant`)                                             |
| `control`        | the erasure/privacy control at `DELETE`/retention time: `redact`, `none`, `forbid`                                 |

`control` is the bridge to the controls already built: `redact` is what the
customer erasure and retention sweep do (write the `[redacted]` marker, or
`NULL` where no integer is not a place); `forbid` is what the Debug-redaction
rule and `RefundTarget`'s redacting `Debug` implement — a value that must never
reach a log or export.

## The personal-data columns

Not an exhaustive table here — the authoritative copy is the YAML. The elements
whose `subject` is a person are:

| Element              | Copies (DB)                                                                                                    | Control   |
| -------------------- | -------------------------------------------------------------------------------------------------------------- | --------- |
| `payer_msisdn`       | `customers.phone`, `charges.payer_ref`, `charges.payer_ref_masked`                                             | `redact`  |
| `customer_name`      | `customers.name`                                                                                               | `redact`  |
| `customer_email`     | `customers.email`                                                                                              | `redact`  |
| `address_formal`     | `customers.address_line1`…`address_country`                                                                    | `redact`  |
| `address_gps`        | `customers.address_latitude_microdeg`, `customers.address_longitude_microdeg`                                  | `redact`  |
| `rail_failure_text`  | `charges.failure_raw`, `refunds.failure_raw`, `webhook_deliveries.response_excerpt`, `payment_intents.last_payment_error*`, `provider_requests.error_kind` | `redact`  |
| `staff_email`        | `staff_members.email`                                                                                          | `redact`  |
| `staff_display_name` | `staff_members.display_name`                                                                                   | `none`    |
| `staff_credential_secret` | `credentials.material`/`subject`/`issuer` (migration 0044 moved the staff credential columns here from `staff_members`)     | `forbid`  |
| `staff_oauth_token`  | `staff_sessions.access_token`                                                                                  | `forbid`  |
| `session_oauth_code` | `oauth_codes`, `oauth_refresh_tokens`, `oauth_device_codes`, `oauth_authorization_codes`, `oauth_client_assertion_jtis`, `oauth_dpop_jti` | `forbid` |
| `webhook_url`        | `webhook_deliveries.url`, `checkout_sessions.success_url`/`cancel_url`/`return_url`, `oauth_*redirect_uri`, `charges.redirect_url`/`return_url` | `forbid` |
| `oauth_signing_key`  | `oauth_signing_keys.kid`/`public_jwk`                                                                          | `forbid`  |
| `oauth_client_secret`| `oauth_clients.client_secret_hash`/`jwks`, `merchant_api_keys.key_digest`/`key_prefix`, `checkout_sessions.publishable_key`/`client_secret_suffix`/`return_token`, `payment_intents.client_secret_suffix` | `forbid` |
| `merchant_metadata`  | `customers.metadata`, `payment_intents.metadata`/`description`, `refunds.metadata`, `invoices.metadata` | `none`   |
| `stored_api_body`    | `events.data`, `idempotency_keys.response_body`                                                          | `redact` |
| `merchant_note`      | `refunds.reason`, `invoices.description`, `invoice_items.description`                                           | `none`   |

Everything else is a `sys_*` element (`subject: none`) — identifiers, timestamps,
statuses, amounts, tenancy references, configuration, worker state — classified
for completeness so that a future column is caught in both directions, not
because they hold personal data.

### The `none` controls deserve a note

`merchant_metadata`, `merchant_note` and `staff_display_name` carry `control:
none` deliberately, matching what the erasure already does: `metadata` is the
merchant's own key/value data and is deliberately **not** destroyed on erasure
([customers.md](../flows/customers/privacy-and-erasure.md)); a refund `reason` is
the merchant's free text, the same kind of thing `metadata` is.

`events.data` and `idempotency_keys.response_body` are **not** `merchant_metadata`.
They are their own element, `stored_api_body` (`subject: payer`, `control:
redact`): each stores a complete rendered API object, and when that object is a
customer body it holds payer personal data — which is exactly why the erasure
**rewrites** these copies in the same transaction that erases the customer
([customers.md](../flows/customers/privacy-and-erasure.md)). The honest reading of
`control: redact` here is "the erasure rewrites the payload this container holds",
which is what the erasure statement in `vpay_db::customers` does.

## Non-database surfaces

`schemas/privacy-inventory.yaml` registers the disclosure surfaces ADR-0020 §1
names. Each is marked `enumerable` — whether the gate can currently derive its
contents from a static source independent of the inventory:

| Surface            | Enumerable | Status                                                                                       |
| ------------------ | ---------- | -------------------------------------------------------------------------------------------- |
| `logs`             | no         | no static scanner over `tracing!` sites yet; the Debug-redaction rule is the only guard      |
| `metrics`          | no         | metric-label derivation is not centrally registered                                          |
| `traces`           | yes        | OTLP traces deliberately absent (`docs/status.md`: deferred)                                 |
| `event_store`      | yes        | `events.data` — redacted on customer erasure                                                 |
| `webhook_payload`  | no         | per-event projections (RFC-0002 D2) not yet implemented; payload == API object today         |
| `browser_storage`  | yes        | checkout page local memory on the payer's own device                                         |
| `provider_rail`    | no         | no static scan of adapter request builders; guarded by `RefundTarget`'s redacting `Debug`    |
| `merchant_api`     | no         | wire object projections are per-resource, not centrally registered                           |
| `observability`    | yes        | `/livez` and `/metrics` on `--observability-bind`                                            |
| `backup`           | no         | PITR/WAL and full backups — external store; retention of restore copies is a deployment obligation (RFC-0002 D13) |

A surface with `enumerable: false` is an **unmet criterion**: the gate records it
and keeps #144 open on it rather than manufacturing a self-check (RFC-0002 PR 2).
This page is the record of which surfaces still lack an independent source set.

## Unresolved questions

Every element's `retention` names a **class**, never a period: the customer
class, the auth class, the operational class. The **periods** are RFC-0002 D9
(and the current hard-coded 365-day customer rule is in explicit conflict with
D9's "approved, configurable" requirement — see RFC-0002). Legal basis,
controller/processor role and purpose-necessity approval are RFC-0002 D1 and
are `unresolved`, not guessed.

## Status

**2026-09-16.** The inventory exists and is machine-checked in both directions
against `backends/migrations` by `cargo xtask verify-privacy-inventory`, wired
into `just verify`. Personal-data columns and the non-database surfaces are
registered. What is **not** done: the non-DB `enumerable: false` surfaces lack
independent static scanners (recorded above, not faked); the `@vpay/api-client`
and per-event webhook projections that RFC-0002 D2 needs are unbuilt; and every
RFC-0002 D1–D13 policy answer remains open. This is the foundation stage of the
GDPR epic, not the epic.
