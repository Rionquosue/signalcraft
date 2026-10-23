# Database schema — specification sheet

Schema 1.2 • 23 October 2026 • Proposed implementation contract

## Purpose and companions

This sheet defines every application table in the existing PostgreSQL database: columns, invariants, indexes, retention and access roles. It is authoritative for the data model summarized in 02_Rails_Container_Design.md.

| File | Role |
|---|---|
| 08_schema.sql | Reference DDL for all 54 application tables. Loaded cleanly into PostgreSQL 16. |
| 08_schema_tests.sql | 44 constraint tests (credentials, tenancy, scheduling, delivery, media, integrations, stores and attribution, metrics, relays). All pass against 08_schema.sql. |

Production migrations are written as Rails migrations that produce the same structure; `08_schema.sql` is the reference they are checked against. Solid Queue creates and owns its own `solid_queue_*` tables.

## Conventions

| Topic | Rule |
|---|---|
| PostgreSQL version | 13 or later (uses built-in `gen_random_uuid`, generated columns, `num_nonnulls`). No extensions, so nothing needs superuser on the existing server. |
| Primary keys | `uuid`. The application generates UUIDv7 (time-ordered) values; the DDL default `gen_random_uuid()` is only a fallback. Append-only logs (`outbox_events`, `audit_events`) use `bigint` identity for ordering. |
| Enumerations | `text` with `CHECK (… IN …)`, mapped to string-backed Rails enums. Adding a value is a constraint replacement, not a type migration. |
| Time | `timestamptz` everywhere, stored as UTC. Wall-clock scheduling input is kept separately (see post_targets). |
| Secrets | User passwords are salted one-way hashes (`users.password_digest`). Columns marked *encrypted* hold Active Record Encryption ciphertext (AES-256-GCM, non-deterministic), including OAuth tokens and Bluesky app passwords, which must be recoverable to send to providers. They are never indexed or queried by value. Tokens that must be looked up (sessions, invitations, OAuth state, webhook endpoints, signed URLs) store only a 32-byte SHA-256 digest. |
| Lengths | Every free-text column has a length `CHECK`; JSON columns have a size `CHECK`. |
| Tenancy | Every workspace-owned row carries `workspace_id`. Cross-table references use composite foreign keys on `(id, workspace_id)`, so the database itself prevents a row in one workspace pointing at another workspace's data. Application queries still scope by membership. |
| Deletion | Domain rows are archived, not deleted. Foreign keys default to `RESTRICT`; `CASCADE` is used only for pure child rows (chunks, sessions, memberships, queue entries, checkpoints). Hard deletion is done by maintenance jobs in dependency order. |
| Optimistic locking | `lock_version` on rows edited in forms (posts, post_targets); `version` on channel_queues for reorder. |

## Entity overview

```
users ─┬─ sessions ─ oauth_states
       └─ memberships ─ workspaces ─┬─ invitations
                                     ├─ workspace_plugins ─ plugins ─ plugin_app_registrations
                                     ├─ social_accounts ─┬─ channel_queues ─┬─ queue_slots
                                     │                    │                  └─ queue_entries
                                     │                    ├─ credential_refresh_leases
                                     │                    ├─ plugin_records
                                     │                    ├─ webhook_endpoints ─ webhook_events
                                     │                    └─ remote_media_handles ─ plugin_checkpoints
                                     ├─ posts ─┬─ post_media
                                     │         └─ post_targets ─┬─ post_target_media
                                     │                          ├─ queue_entries
                                     │                          └─ publish_intents ─ publish_attempts ─┬─ publish_attempt_media
                                     │                                                                 ├─ plugin_checkpoints
                                     │                                                                 └─ signed_media_urls
                                     └─ media_assets ─┬─ media_chunks
                                                      ├─ upload_sessions
                                                      └─ processing_requests
Insights (09):   store_accounts ─┬─ store_products ─ store_product_stats
                                  ├─ store_orders ─ store_order_items ─ attribution_allocations
                                  └─ attribution_codes ─ (social_accounts)
                 tracked_links (per target or profile) ─┬─ link_clicks
                                                         └─ link_click_daily
                 post_targets ─┬─ post_metric_polls
                               └─ post_metric_snapshots
                 fx_rates, cost_entries
Relays (10):     integration_tokens, relay_deliveries ─ relay_media_grants
Deployment-wide: plugins, plugin_app_registrations, provider_throttles, provider_usage,
                 login_throttles, outbox_events, audit_events, process_heartbeats
```

## Identity and tenancy

**users** — `email` (unique case-insensitively via `lower(email)`), `password_digest`, `display_name`, `timezone`, `disabled_at`. `password_digest` holds the self-describing salted hash string (Argon2id, or bcrypt where the pinned Rails lacks Argon2 support), as defined in 02, Credential storage. A check constraint accepts only Argon2id or bcrypt hash strings, so a plaintext or unsalted value cannot be stored even by a bug.

**sessions** — `user_id`, `token_digest` (unique), `ip_address`, `user_agent`, `last_seen_at`, `expires_at`. Password reset tokens are signed, expiring Rails tokens (`generates_token_for`) and need no table.

**login_throttles** — keyed by `key_digest` (hash of email or IP) with `scope`, `window_started_at`, `attempt_count`, `locked_until`. Shared across all web processes.

**workspaces** — `name`, `default_timezone`, `media_quota_bytes`, `media_reserved_bytes`, `reporting_currency` (default USD), `attribution_window_days` (1–30, default 7), `attribution_half_life_hours` (default 48), `archived_at`. `media_reserved_bytes` is increased when an upload session is created and decreased when an asset is deleted, both under a `SELECT … FOR UPDATE` on the workspace row; a nightly job reconciles it against the sum of asset sizes.

**memberships** — unique `(workspace_id, user_id)`, `role` in owner / editor / viewer. "At least one owner per workspace" is enforced by the application inside the transaction that changes roles.

**invitations** — `email`, `role`, `token_digest`, `invited_by`, `expires_at`, `accepted_at`, `revoked_at`. At most one open invitation per workspace and email.

## Plugins and provider connections

**plugins** — one row per installed plugin, synced from the image's plugin registry at boot: `plugin_id` (matches the manifest ID pattern), `kind` (social or commerce), `version`, `plugin_api`, `manifest`, `load_status` (loaded / failed / missing), `load_error`. A plugin removed from the image stays as `missing` so history keeps its references.

**workspace_plugins** — per-workspace enablement and settings: `enabled`, `settings` (≤ 64 KiB), `settings_schema_version`, `enabled_by`, `enabled_at`.

**plugin_app_registrations** — the provider app a connection uses, unique per `(plugin_id, instance_host)`. `credentials_source` is `stored` (encrypted `client_credentials`, for example a Mastodon app registered per instance) or `operator_config` (client ID and secret come from deployment secrets, for example X, YouTube, TikTok, Instagram). Every social account references one registration, so app-level quotas and app-level webhooks have a single key.

**social_accounts** — `plugin_id`, `plugin_app_registration_id`, `provider_account_id`, display fields, encrypted `credentials`, `credentials_version`, `granted_scopes`, `credentials_expires_at`, `connection_status` (connected / reauthorization_required / disconnected / plugin_unavailable), cached `capabilities` with `capabilities_fetched_at`.
- Unique `(workspace_id, plugin_app_registration_id, provider_account_id)`: one connection per provider account per workspace. The same provider account may be connected in two workspaces.
- The registration must belong to the same plugin (composite foreign key).
- A connected account must have credentials.

**credential_refresh_leases** — one row per account being refreshed: `lease_owner`, `acquired_at`, `lease_expires_at`. Taken and released in short transactions; never a lock held across HTTP. `credentials_version` on the account is the compare-and-swap value (see 02, Credential refresh).

**oauth_states** — `state_digest`, `session_id`, `user_id`, `workspace_id`, `plugin_app_registration_id`, optional `reauthorize_social_account_id`, encrypted `pkce_verifier`, `expires_at`, `consumed_at`. The database rejects lifetimes over 10 minutes. Single use is enforced by setting `consumed_at` with `UPDATE … WHERE consumed_at IS NULL` and checking one row changed.

**webhook_endpoints** — `token_digest` (the opaque URL token), encrypted `webhook_secret`, `state` (active / rotating / revoked), `rotation_ends_at`. Bound to exactly one social account, one store account or one app registration (database-enforced).

**webhook_events** — deduplication per app registration (social events) or per store account (store events), with `outcome` and timestamps. An app-level event naming a provider account is fanned out to every connected social account with that registration and provider account ID.

**plugin_records** — per-account plugin state: `schema_version`, `data` (≤ 64 KiB).

**provider_throttles** — unique `(plugin_id, scope, scope_key)` where scope is account (key = social account ID), provider (key empty) or provider_app (key = registration ID); `retry_at`, `quota_remaining`, `quota_resets_at`.

**provider_usage** — paid-API budget accounting per plugin per calendar month (`period_start` is the 1st): `billable_requests`, `reserved_cost_micros`, `committed_cost_micros`. Before submission a job locks the month's row, checks `committed + reserved + estimate ≤ budget`, adds the estimate to `reserved` and to the attempt's `cost_reserved_micros`, and commits. After the provider responds, it moves the amount to `committed`. A sweeper releases reservations of attempts that ended without submission.

## Media

**media_assets** — one row per stored file.

| Column group | Columns |
|---|---|
| Identity | `workspace_id`, `kind` (original / variant), `source_asset_id`, `variant_key` (canonical hash of operation and parameters) |
| Lifecycle | `state`: uploading → uploaded → validating → ready, or rejected / failed / expired; `ready_at`, `rejection_code` |
| Content | `byte_size` (≤ 256 MiB), `sha256`, `declared_content_type`, verified `content_type`, `media_kind` (image / video / audio), sanitized `metadata`, `original_filename` |
| Protection | `protection_declared`, `protection_tool`, `protection_declared_by`, `protection_declared_at` (see 07_Media_Protection_Specification.md) |
| Housekeeping | `uploaded_by`, `gc_marked_at` |

Invariants enforced by the database:
- A variant's source is in the same workspace.
- No variant can be created from a declared-protected original, and protection cannot be declared on an original that still has variants. This is done by a composite foreign key on `(source_asset_id, workspace_id, source_protection_declared)` with `source_protection_declared` fixed to false.
- Protection can be declared only on originals that are images (or not yet probed).
- `sha256` is present from `uploaded` onward; `ready` requires verified type and kind; `rejected` requires a code.
- One active variant per `(source_asset_id, variant_key)`.
- Deduplication: one ready original per `(workspace_id, sha256, protection_declared)`. When a finished upload matches an existing asset, the application points references at the existing asset and expires the duplicate.

**media_chunks** — `(media_asset_id, seq)` primary key, `data bytea` with storage `EXTERNAL` (stored out of line, no pointless compression of already-compressed media). Chunks are 1 byte to 8 MiB (default 2 MiB). Large assets are deleted chunk-batch by chunk-batch before the asset row, to keep transactions and WAL bursts small.

**upload_sessions** — `media_asset_id` (one session per asset), `user_id`, `expected_size`, `chunk_size`, generated `expected_chunks`, `expires_at`, `completed_at`. The per-user concurrent upload limit counts rows with `completed_at IS NULL`. Received chunks are read from `media_chunks`, not duplicated here.

**processing_requests** — one FFmpeg service job: `source_asset_id`, `operation`, `parameters`, `output_format`, `variant_key`, `idempotency_key` (unique, sent to the service), `state` (pending / submitting / submitted / downloading / completed / failed / abandoned), `remote_instance_id`, `remote_job_id`, `result_asset_id`, `error_code`, `retryable`, `attempt_count`, `next_attempt_at`, `remote_deleted_at`. Validation of an original is a `metadata` request. At most one live request per `(source_asset_id, variant_key)`. The cleanup index finds finished jobs whose remote copy has not been deleted.

## Posts, targets and queues

**posts** — shared draft: `body` (≤ 20,000 characters), `revision`, `lock_version`, authorship, `archived_at`.

**post_media** — ordered shared attachments: `media_asset_id`, `position` (0–19), `alt_text`. Position uniqueness is deferrable so reordering is one transaction.

**post_targets** — one scheduled publication to one account.

| Column group | Columns |
|---|---|
| Identity | `post_id`, `social_account_id`, `occurrence` (unique per post and account, so an account can deliberately receive the same post twice) |
| Content overrides | `body_override`, `media_overridden` (when true, `post_target_media` replaces `post_media`), `provider_options` |
| Schedule | `mode` (manual / queue / now), `due_at` (UTC), manual input as `scheduled_local_at` + `scheduled_timezone` + `scheduled_utc_offset_seconds` (the chosen offset resolves repeated DST times) |
| State | `state`, `attention_reason`, `blocked_reason`, `revision`, `lock_version`, `next_poll_at`, `retry_at` |
| Metrics polling | `metrics_next_poll_at`, `metrics_stage` (only on published targets) |
| Claim | `claim_owner`, `claim_expires_at`, `fencing_token` (incremented on every claim) |
| Result | `published_at`, `remote_post_id`, `remote_url` |

State values and reasons:

| state | Required companion |
|---|---|
| draft, preparing, publishing, failed, cancelled | — |
| scheduled | `due_at`, except a queue target waiting for a slot |
| retry_wait | `retry_at` |
| awaiting_provider | `next_poll_at` |
| published | `published_at` |
| needs_attention | `attention_reason`: publication_unconfirmed, schedule_missed, unsupported_checkpoint_version |
| blocked | `blocked_reason`: account_disconnected, reauthorization_required, plugin_unavailable, plugin_disabled, validation_failed, budget_exhausted, protected_media_incompatible, media_unavailable, fetch_url_unavailable |

Reasons are present exactly when their state is, so labels never have to be guessed. For queue targets, `due_at` equals the entry's `slot_occurrence_at`; both are written in the same transaction, and a consistency check query runs in the nightly job.

Dispatcher indexes are partial, so each scan reads only live rows: due scheduled targets, pending provider polls, retry times and expired claims.

**post_target_media** — per-target attachments, same shape as `post_media`, used only when `media_overridden`.

**channel_queues** — one per social account: `timezone`, `paused`, `paused_at`, `paused_by`, `version`.

**queue_slots** — `iso_weekday` (1 = Monday) and `local_time`, unique per queue.

**queue_entries** — `post_target_id` (unique), `rank`, `queue_slot_id`, `slot_occurrence_at` (concrete UTC instant).
- Unique `(channel_queue_id, slot_occurrence_at)`: no two entries claim one slot occurrence.
- Unique `(channel_queue_id, rank)`.
- Both are deferrable, so a reorder can rewrite every rank and occurrence in one transaction and is checked at commit.
- `queue_slot_id` records which slot an occurrence came from. Deleting the slot sets it to null and keeps `slot_occurrence_at`, because the occurrence is the assignment; a slot reference without an occurrence is rejected.
- Composite foreign keys guarantee the entry, its queue and its target all belong to the same account.

## Delivery

**publish_intents** — the unit that owns an idempotency key: `post_target_id`, `target_revision`, `kind` (scheduled / publish_now / manual_retry), `idempotency_key` (unique), `state` (open / closed), `created_by`. At most one open intent per target. Retries of the same intent reuse its key; an explicit new publication creates a new intent.

**publish_attempts** — one claim and send: `publish_intent_id`, `post_target_id`, `attempt_number`, `fencing_token`, `plugin_id`, `plugin_version`, `snapshot` (the TargetSnapshot), `content_hash`, `state` (claimed / submitting / pending / published / not_published / unknown / failed / abandoned), `delivery_state`, timing, remote IDs, encrypted `receipt`, normalized error fields, `retry_at`, and cost reservation columns.
- Unique `(post_target_id, fencing_token)`: a fencing token is used by one attempt only, so a stale worker cannot record a second attempt under an old claim.
- A trigger makes `snapshot`, `content_hash`, intent, target and fencing token immutable after insert.
- `submitted` or `unknown` delivery requires `submission_started_at`; `published` requires a remote ID or URL.

**publish_attempt_media** — exactly which asset and SHA-256 was sent at each position. This is the receipt evidence that declared-protected images were sent unchanged.

**remote_media_handles** — the `prepare_media` result per `(social_account_id, media_asset_id, plugin_id)`: `state` (pending / ready / failed / expired), encrypted `handle`, `expires_at`, `next_poll_at`, `attempt_count`.

**plugin_checkpoints** — encrypted plugin JSON with `schema_version`, owned by exactly one publish attempt or one remote media handle. Plaintext is limited to 64 KiB by the host; the column limit allows for encryption overhead.

**signed_media_urls** — provider-fetch URLs: `token_digest`, `media_asset_id`, `publish_attempt_id`, `expires_at`, `revoked_at`, fetch counters. Revocation sets `revoked_at`; the media role checks it on every fetch.

## Stores, tracked links and attribution

Defined by 09_Insights_and_Attribution_Specification.md; populated by commerce addons (02-7, 02-8).

**store_accounts** — a connected storefront: `plugin_id`, `provider_store_id`, encrypted `credentials`, `connection_status`, `fee_settings` (the addon's fee fields, for estimating fees the store does not report), `addon_state` (import cursors, ≤ 64 KiB), import timestamps and last error. Unique per workspace, plugin and store.

**store_products** — `provider_product_id`, `name`, `url`, `currency`, `list_price_minor`, `active`. **store_product_stats** keeps daily store-side counters where the store reports them (itch.io page views, downloads, purchases).

**store_orders** — one imported order: `provider_order_id` (unique per store account, so re-imports update rather than duplicate), `ordered_at`, `status` (completed / refunded / partially_refunded), `currency`, `gross_minor`, `refunded_minor`, `fee_minor`, `fee_estimated`, generated `net_minor` = gross − refunded − fee, `codes` used. No buyer personal data columns exist. A completed order has no refund; refunds never exceed gross.

**store_order_items** — `(store_order_id, store_product_id)`, `quantity`, `gross_minor`.

**attribution_codes** — a store code linked to one social account (02-8): `code` (unique per store, case-insensitively), `kind` (discount / affiliate), `provider_code_id`, `terms_summary`.

**tracked_links** — `code` (10 base62 characters, unique), `social_account_id`, `post_target_id` (null for an account's profile link), `store_product_id`, `destination_url` (HTTPS only), `utm_enabled`, `disabled_at`. A post link's target must belong to the same account (composite foreign key). One active profile link per account and destination.

**link_clicks** — raw clicks: `occurred_at`, 16-byte daily-rotating `visitor_digest`, `referrer_host`, `is_bot` and `bot_reason` (present exactly when `is_bot`). No IP address or cookie column exists. Deleted after 90 days. **link_click_daily** keeps per-link daily totals: human clicks, unique visitors, bot clicks.

**attribution_allocations** — the model's output per order line: `model_version`, `attribution_method` (code / click_share / unattributed), `social_account_id`, `tracked_link_id`, `attribution_code_id`, `share` (0–1], `net_allocated` (order currency, minor units, four decimals), `computed_at`. Enforced: code allocations credit the whole line to one account; click-share allocations name a tracked link; unattributed allocations name no account. One row per line, model version, method and link. Shares per line summing to 1 is checked by the recompute job and by a nightly consistency query.

**fx_rates** — `(currency, rate_date)` with `per_eur` and `source`; conversions go through EUR.

**cost_entries** — manual monthly costs per account, per platform (`plugin_id`) or workspace-wide. Paid API costs are not entered here; they are summed from `publish_attempts.cost_committed_micros` and `post_metric_polls.cost_micros`.

## Post metrics

**post_metric_polls** — one row per fetch: `stage`, `polled_at`, `outcome` (ok / unavailable / error), `error_code`, `cost_micros`.

**post_metric_snapshots** — `(post_target_id, metric_key, captured_at)`, `value` (non-negative), `provider_name`. `metric_key` is limited to the normalized keys in 04, so an addon cannot invent a metric. A missing row means "not reported", never zero.

## Relays

Defined by 10_Relay_Bot_Protocol_Specification.md.

**integration_tokens** — digests of pull-mode tokens a relay uses to call Rails, grouped by `link_id`, with `last_used_at` and `revoked_at`.

**relay_deliveries** — one per publish attempt to a relay destination: `mode`, `idempotency_key`, `status` (due / leased for pull; queued / sending for push; then delivered / failed / unknown / cancelled), `lease_expires_at` (present exactly while leased; push deliveries are never leased), and the relay's reported `result`.

**relay_media_grants** — single-delivery media URL tokens (digest only) with expiry, served by the relay media route.

## Dispatch, audit and operations

**outbox_events** — `bigint` identity order, `event_type`, `subject_type`, `subject_id`, `payload` (≤ 16 KiB), `available_at`, `dispatched_at`, `attempt_count`, `last_error`. Written in the same transaction as the change it announces. The dispatcher reads `WHERE dispatched_at IS NULL ORDER BY available_at, id … FOR UPDATE SKIP LOCKED`.

**audit_events** — append-only: `occurred_at`, `workspace_id`, `actor_type` (user / system / plugin), `actor_user_id`, `actor_label`, `action`, `subject_type`, `subject_id`, sanitized `details` of what changed (≤ 64 KiB, never secrets; not named `changes`, which clashes with Active Record), `request_id`, `ip_address`. Deliberately has no foreign keys so history survives deletions. A BRIN index on time keeps range scans cheap as the table grows.

**process_heartbeats** — `process_key`, `role` (web / media / worker), `hostname`, `release`, `started_at`, `last_seen_at`. Used by monitoring and by the release-compatibility check during deploys.

## Key transactions

| Operation | Transaction outline |
|---|---|
| Claim a due target | `SELECT … FROM post_targets WHERE state = 'scheduled' AND due_at <= now() … FOR UPDATE SKIP LOCKED`; check account not paused and throttles clear; increment `fencing_token`; set `claim_owner`, `claim_expires_at`, state `preparing`; open or reuse the intent; insert the attempt with snapshot. Commit before any HTTP. |
| Record a provider result | `UPDATE publish_attempts … WHERE id = $1`, then `UPDATE post_targets … WHERE id = $2 AND fencing_token = $3`; zero rows means the claim was superseded and the worker stops. |
| Reorder a queue | Lock the `channel_queues` row, compare `version`, rewrite ranks and slot occurrences for future entries, update matching `post_targets.due_at`, increment `version`, write an outbox event. Deferred constraints check uniqueness at commit. |
| Finish an upload | Verify chunk count and sizes from `media_chunks`, compute SHA-256 by streaming chunks, set `sha256` and state `uploaded`, mark the session complete, create the `metadata` processing request and outbox event. |
| Declare protection | Allowed only while the asset has no variants (the foreign key rejects it otherwise); retire unused variants first. Writes an audit event. Scheduled targets using the asset get a new revision. |

## Retention

| Data | Kept for | Removed by |
|---|---|---|
| Sessions | Until `expires_at` | Hourly cleanup |
| OAuth states | 1 day after expiry | Hourly cleanup |
| Login throttles | 1 day after last update | Daily cleanup |
| Upload sessions and their incomplete assets | 24 hours | Hourly cleanup (chunks deleted in batches) |
| Outbox events | 7 days after dispatch | Daily cleanup |
| Webhook events | 30 days | Daily cleanup |
| Signed media URLs and relay media grants | 7 days after expiry | Daily cleanup |
| Raw link clicks | 90 days | Daily cleanup (daily totals kept) |
| Post metric snapshots and polls | 2 years | Monthly cleanup |
| Store orders, items and allocations | Indefinitely (business records without personal data) | — |
| FX rates | Indefinitely | — |
| Relay deliveries | 90 days after completion | Daily cleanup |
| Processing requests | 30 days after completion, once the remote job is deleted | Daily cleanup |
| Published history (targets, intents, attempts, receipts) | Indefinitely, unless the workspace sets a policy | — |
| Audit events | 400 days by default (operator-configurable) | Monthly cleanup by the maintenance role |
| Media assets | While referenced by a post, target, attempt in retained history, processing request or remote handle | Garbage collector (mark, then delete after a grace period) |

## Database roles and grants

| Role | Privileges |
|---|---|
| `social_migrator` | Owns all tables; DDL. Used only by the migrate role at deploy time. |
| `social_app` | `SELECT, INSERT, UPDATE, DELETE` on application tables, except `audit_events` (`SELECT, INSERT` only). Used by web, media and worker. |
| `social_maintenance` | `social_app` plus `DELETE` on `audit_events`. Used only by the retention job. |
| `social_readonly` (optional) | `SELECT` on non-secret tables for reporting; no access to columns holding ciphertext or digests. |

Solid Queue tables are owned by `social_migrator` and used by `social_app`. The connection budget (02, Configuration and capacity) applies across all roles.

## Migration rules

- Create indexes on existing large tables with `CREATE INDEX CONCURRENTLY` (in a migration with `disable_ddl_transaction!`).
- Add foreign keys and checks to existing tables as `NOT VALID`, then `VALIDATE CONSTRAINT` in a later migration.
- Never rewrite `media_chunks` in a migration; it holds most of the database's bytes.
- Format changes to JSON columns (checkpoints, plugin records, settings, snapshots) follow the two-release rule in 02: read both formats first, write the new one later.
- Removing a column takes two releases: stop reading it, then drop it.
- `db/structure.sql` (not `schema.rb`) is the Rails schema format, because the design relies on partial and expression indexes, deferrable constraints, generated columns and a trigger.

## Capacity notes

Media dominates storage: `media_chunks` will be most of the database, and of WAL and backups. Everything else is small; at 10,000 targets per month, delivery tables grow by tens of megabytes per year. Monitor `media_chunks` bloat and autovacuum after large deletions (02, Storage characteristics).

## Changes in 1.2

- `queue_entries`: a slot reference now only requires an occurrence (`queue_entries_slot_needs_occurrence`), instead of the two being null together. The old rule made it impossible to delete a slot still referenced by an entry, because `ON DELETE SET NULL` left an occurrence without a slot.

## Changes in 1.1

- Added store, tracked-link, click, attribution, FX and cost tables (09); post metric polls and snapshots; relay tokens, deliveries and media grants (10).
- Renamed `audit_events.changes` to `details` and `attribution_allocations.method` to `attribution_method` (both names clash with Ruby or Active Record methods). Addon ids may be 1 to 64 characters.
- `plugins.kind`, workspace insights settings, store-account webhook endpoints, metrics polling columns on `post_targets`.

## Changes to other sheets

- 02: the data model table defers to this sheet; `attention_reason` gains `unsupported_checkpoint_version`.
- 05: the status table shows the new attention reason.
- 07: protection columns and the variant rule are defined here.

## Acceptance criteria

- `08_schema.sql` loads without errors on the target PostgreSQL version.
- `08_schema_tests.sql` passes on every schema change.
- Rails migrations produce a `structure.sql` equivalent to `08_schema.sql` (compared in CI).
- Runtime roles cannot run DDL or delete audit events.
- Dispatcher queries use the partial indexes (checked with `EXPLAIN` in CI against seeded data).
