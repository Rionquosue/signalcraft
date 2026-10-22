# Ruby on Rails container — design sheet

Specification 1.2 • 22 October 2026 • Proposed implementation contract

## Purpose

A lightweight social publishing application with shared drafts, independent account schedules, reusable channel queues, and plugin-based platform integrations. All durable application data and media reside in the existing PostgreSQL installation. HTTP is served behind the operator's existing HTTPS reverse proxy.

Integrations are Ruby addons, each with its own sheet numbered under this one (04 has the contract and index):

| Sheet | Addon | Kind |
|---|---|---|
| 02-1 | Instagram | social |
| 02-2 | TikTok | social |
| 02-3 | YouTube | social |
| 02-4 | X | social |
| 02-5 | Bluesky | social |
| 02-6 | Mastodon | social |
| 02-7 | itch.io | commerce (store sales for Insights) |
| 02-8 | Jinxxy | commerce (store sales for Insights) |
| 02-9 | Discord through your self-hosted YAGPDB fork | social, relay |
| 02-10 | Telegram through your own bot | social, relay |

Instagram, TikTok and YouTube require media on every post; Instagram additionally requires a public media origin. Relay addons use the protocol in 10_Relay_Bot_Protocol_Specification.md. Store sales, tracked links and post metrics feed the Insights area (09_Insights_and_Attribution_Specification.md).

## Image and process model

One application image runs up to three long-lived service roles and a one-shot migration role.

| Role | Command | Responsibilities |
|---|---|---|
| web | bundle exec puma -C config/puma.rb | UI, authentication, OAuth callbacks, webhooks, tracked-link redirects (`/r/{code}`), relay pull API |
| media | bundle exec puma -C config/puma_media.rb | Chunked uploads, range previews, signed provider fetches, relay media grants |
| worker | bin/jobs | Solid Queue dispatch, processing orchestration, publishing and reconciliation, metrics polling, store imports, attribution recompute, FX rates |
| migrate | bin/rails db:migrate | Deployment-only schema migration under separate credentials |

The media role is the same image and code with its own Puma configuration and thread pool. The proxy routes `/uploads/*`, `/media/*` and `/fetch/*` to it so that slow media clients cannot starve UI requests. Small deployments may run media routes in the web role, but must then raise its thread budget (see Configuration and capacity) and accept that a few slow clients can delay the UI.

Use supported, pinned Ruby and Rails releases with a lockfile; Rails 8.1 is the planning baseline, subject to support verification at implementation. Prefer a slim Debian runtime for Ruby/native-gem compatibility; Alpine is required only for the FFmpeg service. Compile assets and native gems in a build stage. Ship no FFmpeg, FFprobe or image-decoding utilities in Rails.

Use Hotwire, Turbo, Stimulus, Importmap and Propshaft. Initial refresh uses bounded polling/Turbo requests, avoiding an extra persistent pub/sub component. PostgreSQL backs Solid Queue; no Redis or local durable media store.

## Deployment topology

| Service | Networks | Inbound access |
|---|---|---|
| web | Existing proxy network + private database network + controlled outbound network | Proxy to HTTP 3000 |
| media | Existing proxy network + private database network | Proxy to HTTP 3001 |
| worker | Database + dedicated media + controlled outbound network | No application listener |
| FFmpeg API | Dedicated internal media network | Worker to HTTP 8080 |
| YAGPDB fork (optional, 02-9) | Operator's YAGPDB stack + a private relay network shared with worker and media | Worker to YAGPDB web relay API; YAGPDB feeds service to media relay media route |
| Telegram bot (optional, 02-10) | Operator-defined | Push: worker to the bot's relay API. Pull: the bot to web's relay API and media's relay media route |
| Existing PostgreSQL | Existing private database network | web, media, worker and migration role only |

Do not recreate PostgreSQL, replace its volume or publish its database port. The operator supplies its reachable DNS name, database, credentials and network name. A remote database instead uses verified TLS and a private reachable endpoint.

The external proxy supplies HTTPS. Configure the public canonical origin, secure cookies and Rails HTTPS assumptions for that deployment; reject unexpected hosts. Strip untrusted forwarded headers at the proxy and restrict direct Puma access. Container networking alone does not make arbitrary forwarded headers trustworthy. Set the proxy request-body limit for upload routes to the chunk size plus a small overhead (for example 2.5 MiB) and for all other routes to a small value (for example 1 MiB).

Signed provider-fetch URLs (see PostgreSQL media storage) require `PUBLIC_MEDIA_BASE_URL` to be reachable from the public internet. If the deployment is LAN-only, leave it unset: the host then reports fetch-by-URL as unavailable, and plugins that need it disable media for affected accounts with an explanation. In the v1 provider set this makes Instagram unusable, since Instagram only accepts media it fetches from a public URL. Bluesky's atproto OAuth similarly needs a publicly reachable client metadata URL; LAN-only deployments fall back to Bluesky app passwords.

## Durable data model

This table is a summary. 08_Database_Schema_Specification.md and its reference DDL (08_schema.sql) are authoritative for tables, columns, constraints and indexes.

| Entity | Key fields and invariants |
|---|---|
| users, workspaces, memberships | Workspace-scoped roles: owner, editor, viewer |
| social_accounts | Workspace, plugin ID/version, provider account ID, encrypted credentials, credentials_version, connection status |
| credential_refresh_leases | Account (unique), lease owner, lease expiry; short-lived row, never held as a database lock |
| webhook_endpoints | Plugin ID, social account or plugin app registration, hashed opaque endpoint token, encrypted webhook secret, active/rotating state |
| posts | Shared draft and revision; no single authoritative publication time |
| post_targets | Post + social account + occurrence, override content, mode, due_at, state, attention_reason, next_poll_at, revision |
| channel_queues | One account queue, timezone, pause state, version |
| queue_slots | Weekdays and local wall-clock times; unique (queue, weekday, local time) slot definition |
| queue_entries | Target, rank, assigned slot occurrence (UTC instant); unique (queue, slot_occurrence_at) |
| media_assets | Workspace, size, checksum, verified type, readiness, validation state, source/variant link |
| media_chunks | Asset, zero-based sequence, BYTEA data (storage EXTERNAL); unique asset/sequence |
| upload_sessions | Asset, expected size, chunk size, received sequence set, expiry, uploader |
| processing_requests | Source revision, operation, remote boot/job ID, idempotency key, state and retry count |
| publish_attempts | Target snapshot, attempt ID, idempotency key, receipt, outcome |
| plugin_checkpoints | Publish attempt or media preparation, plugin ID, schema_version, encrypted JSON (≤ 64 KiB) |
| remote_media_handles | Social account, asset, plugin ID, encrypted handle, expires_at; unique (account, asset, plugin) |
| plugin_records | Plugin-namespaced per-account JSONB configuration/state with schema version |
| plugin_app_registrations | Plugin ID, instance host, encrypted client credentials; unique (plugin, host); for example one Mastodon app per instance |
| provider_throttles | Plugin ID, scope (account, provider, provider_app), scope key, retry_at, remaining quota where known |
| provider_usage | Plugin ID, period, billable request count and estimated cost; used for X budget limits |
| outbox_events | Durable dispatch intents written in the same transaction as target changes |
| audit_events | Actor, action, target and sanitized changes |
| solid_queue_* | Durable job execution metadata |

Index workspace/state/due_at, account/due_at, state/next_poll_at, post target lookup and chunk sequence. Foreign keys enforce ownership relationships; every query and download must authorize workspace membership. IDs alone confer no access.

`attention_reason` is required when state is `needs_attention` and null otherwise. Values: `publication_unconfirmed`, `schedule_missed`, `unsupported_checkpoint_version`. `blocked` likewise requires a `blocked_reason` (values in 08).

## PostgreSQL media storage

Use a custom chunk repository; optionally expose an Active Storage service adapter only if its streaming contract is verified. Default chunks are 2 MiB.

### Chunked upload protocol

A single large request body cannot be streamed into Rails without touching disk, because Puma reads request bodies over about 112 KB into a temporary file before the application sees them. Uploads therefore use browser-side chunking:

1. `POST /uploads` with expected byte size and declared type creates an incomplete asset and an `upload_sessions` row. The response gives the session ID, chunk size and expiry. Reject sizes above `MAX_UPLOAD_BYTES` here.
2. `PUT /uploads/{session}/chunks/{sequence}` sends one raw `application/octet-stream` body of exactly the chunk size (the last chunk may be shorter). The server writes it to `media_chunks` in one short transaction. Re-sending an already stored sequence with identical bytes is a no-op; different bytes return 409.
3. `GET /uploads/{session}` returns the received sequences so an interrupted browser can resume.
4. `POST /uploads/{session}/complete` verifies byte count and contiguous chunks, computes SHA-256 by streaming the chunks from PostgreSQL, and moves the asset to `uploaded` (not yet validated).

Each chunk passes through at most one bounded Puma request buffer. Set `TMPDIR` to a memory-backed tmpfs sized for the media role's threads × (chunk size + overhead); these buffers are transient, deleted at request end, and never hold a whole media file. Limit concurrent upload sessions per user (`MAX_UPLOADS_PER_USER`, default 2). Abandoned sessions and their chunks expire after 24 hours.

### Validation, previews and processing

Raw uploads are untrusted until the isolated processor returns validated metadata. Until then, the UI shows a placeholder and Rails does not serve the bytes back to browsers. After validation, previews are served:

- with byte ranges, without concatenating the file, and with each 206 response capped at `MAX_RANGE_RESPONSE_BYTES` (default 8 MiB) so a thread is not held for a whole file;
- with the server-assigned Content-Type from validated metadata, never the client's declared type;
- with `X-Content-Type-Options: nosniff`, `Content-Security-Policy: sandbox` and `Content-Disposition: inline` only for an allowlist of image, audio and video types; everything else is `attachment`.

Stream source chunks to FFmpeg and result bytes into a new incomplete asset. Commit output readiness before requesting remote deletion. On worker start, and periodically, issue DELETE for every remote job recorded in `processing_requests` whose result is committed or abandoned, so orphaned outputs do not occupy processor capacity. Deduplicate only inside a workspace and after verified checksums. Garbage collection must consider drafts, scheduled targets, active processing and published-history retention; use relational references plus transactional marking, not an unguarded decrementing counter.

An image the author has declared protected against AI training (see 07_Media_Protection_Specification.md) is published byte-for-byte as uploaded: no provider variants are generated from it, and a provider whose limits it breaks is blocked rather than served an adjusted copy.

### Storage characteristics

Originals and variants stay in PostgreSQL. Set `ALTER TABLE media_chunks ALTER COLUMN data SET STORAGE EXTERNAL` so already-compressed media is stored out of line without pointless TOAST compression. Plan for media volume in database size, WAL generation, replication and backup duration; enforce a per-workspace media quota (`WORKSPACE_MEDIA_QUOTA_BYTES`) and expose storage use in the owner dashboard. Large deletions leave dead tuples: monitor autovacuum on `media_chunks` and schedule space reclamation during maintenance windows.

### Signed provider fetches

Temporary signed HTTPS media URLs may be issued by Rails for provider fetches, only when `PUBLIC_MEDIA_BASE_URL` is set. Each URL is scoped to one immutable validated asset, with configurable expiry and revocation, served by the media role. Never expose internal FFmpeg URLs.

## Scheduling semantics

A post is a shared authoring object. Each post target is one independently scheduled publication to one connected account. The same post can publish to Bluesky at 09:00, Mastodon at 12:30 and Instagram tomorrow at 08:00.

| Mode | Behavior |
|---|---|
| Manual | Fixed timestamp for this target; queue reordering cannot move it |
| Queue | Occupies the next eligible recurring slot occurrence on that account; rank determines order |
| Now | Becomes due immediately after explicit user action and validation |

Store timestamps in UTC and the selected IANA timezone alongside scheduling input. Queue slots are evaluated in the account timezone; each assignment stores the concrete slot occurrence as a UTC instant, and the unique (queue, slot_occurrence_at) constraint prevents two entries claiming the same occurrence. On a nonexistent daylight-saving wall time, skip that slot; on a repeated wall time, use its first occurrence once. Manual ambiguous times require an offset choice; nonexistent times are rejected with the next valid time offered. Manual targets may share a time with a queue occurrence on the same account; the UI warns about minimum spacing rather than preventing it.

Queue reorder locks the channel, verifies its version, and atomically recomputes future queue assignments only. Show a preview of affected dates. Schedule edits likewise require preview and commit. Manual timestamps remain fixed; warn about provider limits and minimum spacing rather than shifting them silently.

### Lateness and missed schedules

The dispatcher runs every `DISPATCH_INTERVAL_SECONDS` (default 15). A target is late when it has not been claimed by its due time. Within `MISSED_SCHEDULE_GRACE_SECONDS` (default 900) of its due time, a late target publishes normally. Beyond the grace window:

- queue-mode targets are reassigned to their next future slot occurrence;
- fixed-time targets become `needs_attention` with `attention_reason = schedule_missed`, for explicit publish-now or reschedule.

Pause prevents new publish claims for that account, including scheduled manual and immediate requests. In-flight provider requests may complete. Resume applies the lateness rule above to everything due while paused. After worker outages, apply the same rule. Never flood overdue posts automatically.

## Publishing state and delivery

`draft → scheduled → preparing → publishing → published`

`publishing → awaiting_provider → published` when the provider accepts the request but reports processing (a plugin `pending` result).

Branches: `retry_wait`, `blocked`, `needs_attention`, `failed`, `cancelled`. Queue membership and account pause are separate from target state. `blocked` includes disconnected accounts or missing plugins.

Write scheduling changes and an outbox event atomically. A recurring dispatcher drains the outbox and scans due targets, tolerating duplicate jobs. Claim a target under a row lock with a lease and fencing version; record an immutable content snapshot and stable remote idempotency key before network activity. Do not hold database locks during HTTP calls.

Jobs recheck target revision, pause state, media readiness and credentials before sending. A stale job exits without publishing. Editing a scheduled target creates a new revision; editing once publishing begins creates a new draft and does not alter the in-flight request.

Each platform's target can be edited on its own at any point before publishing begins: text (`body_override`), media (`post_target_media`) and platform options. Such an edit creates a new revision of that target only, keeps its queue slot or fixed time, and leaves sibling targets untouched. Shared-draft edits update only fields a target has not overridden (05, Editing a queued post for one platform).

`awaiting_provider` targets are polled by new jobs at `next_poll_at` via the plugin's reconcile or resume path; no worker sleeps. A target remaining in `awaiting_provider` past `PROVIDER_PENDING_TIMEOUT_SECONDS` (default 3600) becomes `needs_attention` with `attention_reason = publication_unconfirmed`.

Exactly-once delivery cannot be promised across provider APIs. If a remote call times out after submission, reconcile using the saved receipt/provider idempotency mechanism. If the provider cannot establish the outcome, mark `needs_attention` with `attention_reason = publication_unconfirmed` and prohibit blind retry. A stale publishing lease also requires reconciliation before another send. Retrying one failed target never republishes successful siblings.

### Credential refresh

Credential refresh uses a lease, not a database lock held across HTTP:

1. In a short transaction, insert or take over the account's `credential_refresh_leases` row if absent or expired, and read `credentials_version`. Commit.
2. Call the plugin's `refresh_credentials` with no database locks held.
3. In a short transaction, write the new encrypted credentials only if `credentials_version` is unchanged and the lease is still owned; increment the version and release the lease.

Other jobs needing the account wait on the lease (re-enqueue with a short delay) rather than refreshing in parallel. If the process dies after the provider rotated a refresh token but before step 3, the stored token may no longer be valid; the next refresh failure marks the account `ReauthorizationRequired` and shows a reconnect action. Never retry a rejected rotated refresh token in a loop.

### Retries and rate limits

Enforce rate limits and Retry-After at the scope the plugin reports: per account, per provider, or per provider app (a quota shared by every account using this deployment's API client, such as YouTube's daily upload allowance). For paid APIs such as X, the owner sets a monthly budget (`PROVIDER_BUDGETS`); when it is reached, affected targets become `blocked` with an explanation rather than publishing. Retry transient pre-submission failures with bounded exponential backoff and jitter. Retries are declared explicitly with Active Job `retry_on`/`discard_on`; Solid Queue does not retry failed jobs on its own.

## Security and operations

- Owner installs approved plugin versions at image build; plugins are trusted Ruby code with process privileges.
- No runtime gem installation or arbitrary uploaded Ruby files.
- Non-root UID 10001, read-only root, dropped capabilities, no-new-privileges, bounded memory-backed tmpfs for `TMPDIR` and incidental framework needs.
- Encrypt OAuth and refresh tokens, app passwords, plugin checkpoints, remote media handles and webhook secrets using Active Record Encryption; keep encryption and application keys outside PostgreSQL and image layers (see Credential storage).
- Secure sessions, CSRF protection, salted password hashing (see Credential storage), shared PostgreSQL login throttles, reset-token expiry and owner-controlled user invites.
- Browser CSP; escape user/provider text. Never render uploaded SVG/HTML as trusted application content; media responses follow the preview rules above.
- HTTP client uses TLS verification, bounded responses/timeouts and redirect validation. Private/link-local/metadata destinations blocked, including DNS rebinding. Private federated instances require explicit operator allowlisting.
- Filter tokens, signed URLs, webhook endpoint tokens, private content and provider raw bodies from logs. Audit account changes, publishing actions, schedules and plugin lifecycle.

## Credential storage

The application stores three kinds of secret, and each needs a different treatment. Which one applies depends on whether the application only has to check the secret or has to send it somewhere.

| Secret | Application needs to… | Storage |
|---|---|---|
| Users' login passwords | Check a password someone types | Salted, slow one-way hash |
| Provider credentials (OAuth tokens, Bluesky app passwords, provider client secrets, webhook secrets) | Send the original to a provider | Authenticated encryption, keys outside the database |
| Random lookup tokens (sessions, invitations, OAuth state, webhook URL tokens, signed media URLs, upload sessions) | Match a token presented back to it | SHA-256 digest only |

### User login passwords

Follows the OWASP Password Storage Cheat Sheet.

- **Algorithm:** Argon2id through `has_secure_password algorithm: :argon2` with the `argon2` gem. Set the parameters explicitly rather than relying on gem defaults: at least 19 MiB memory, 2 iterations, parallelism 1. Raise memory if benchmarks allow, keeping one verification well under 0.5 seconds on the web role at its thread count.
- **Version check:** The `algorithm:` option was added to Rails after 8.1. If the pinned Rails release does not include it, use bcrypt (the default `has_secure_password` algorithm) with cost 12 and the built-in 72-byte maximum, and switch to Argon2id when upgrading Rails.
- **Salt:** Every hash gets its own random salt, generated by the algorithm and stored inside the hash string. No separate salt column.
- **Format:** `users.password_digest` stores the self-describing hash string (algorithm, parameters, salt and hash together), so stronger parameters or a new algorithm can be adopted without a schema change.
- **Rehash on login:** After a successful login, if the stored hash uses an older algorithm or weaker parameters than the current configuration, re-hash the password just entered and save it in the same request. Accounts that have not signed in since a change keep their old hash until they do.
- **Pepper:** Not used in v1. OWASP treats it as optional defense in depth; `has_secure_password` has no pepper support, and rotating a pepper forces password resets. Database theft is mitigated by the slow hash and by keeping backups encrypted.
- **Never stored or logged:** plaintext passwords, password lengths or partial hashes. `password` and `password_confirmation` are in Rails parameter filtering.
- **Reset tokens:** `has_secure_password` reset tokens (`generates_token_for`), expiring after 15 minutes and invalidated when the password changes.

### Provider credentials and app passwords

These cannot be hashed: the application must present the original value to the provider, and a hash cannot be reversed. OWASP accepts encryption for exactly this case, signing in to another system that needs the original credential.

- **Encryption:** Active Record Encryption, non-deterministic mode (AES-256-GCM with a random IV per value). No credential column uses deterministic encryption, because those columns are never queried by value and deterministic encryption cannot be key-rotated.
- **Keys:** Primary key, key-derivation salt and any deterministic key are read from secret files, never from the database, image layers or environment dumps. `store_key_references` is enabled so decryption can go straight to the right key during rotation. `support_unencrypted_data` is false.
- **Decryption scope:** Decrypted only inside the plugin call that needs the credential (`context.credentials`), never cached in process memory between calls, never sent to the browser, and filtered from logs and error reports.
- **Bluesky app passwords:** Used only when atproto OAuth is unavailable (for example on a LAN-only deployment); Bluesky recommends OAuth for applications where people sign in. The connection form tells users to create a dedicated app password, never their main password. The app password is stored encrypted and used only to start a new session when the stored refresh token has expired or been rejected. Normal publishing uses the short-lived session tokens. Disconnecting the account deletes the app password and session tokens immediately.
- **Minimizing what is kept:** Only the fields the provider needs are stored. Plugins must not put credentials in checkpoints, plugin records or receipts.

### Key rotation

| Event | Action |
|---|---|
| Scheduled rotation | Every 12 months: append a new primary key (Rails encrypts with the last key in the list and decrypts with any), deploy, run the re-encryption job, verify no ciphertext references the old key, then remove the old key in a later deploy. |
| Suspected key exposure | Rotate immediately as above, then require every connected account to reconnect, since an attacker holding old ciphertext and the old key can still read it. |
| Suspected password-hash exposure | Force password resets for all users and invalidate all sessions. |

The re-encryption job walks each encrypted column in batches, re-saves each row, and is safe to interrupt and resume. Backups taken before a rotation still need the old key to restore, so retired keys are archived with the backups they belong to (see Configuration and capacity, backup).

### Lookup tokens

Session, invitation, OAuth state, webhook URL, signed media URL and upload session tokens are generated with at least 128 bits of randomness and stored only as a SHA-256 digest. A fast hash is appropriate here because the tokens are random rather than human-chosen, so they cannot be guessed from a stolen digest. Comparisons use constant-time equality.

## Configuration and capacity

| Setting | Initial value / source |
|---|---|
| PUBLIC_BASE_URL | Required HTTPS origin |
| PUBLIC_MEDIA_BASE_URL | Optional internet-reachable HTTPS origin for signed provider fetches; unset disables fetch-by-URL |
| DATABASE_HOST/PORT/NAME/USER | Existing PostgreSQL service |
| DATABASE_PASSWORD_FILE | Read-only secret |
| DATABASE_SSLMODE | verify-full for remote DB; explicit local private-network policy |
| SECRET_KEY_BASE / encryption keys | Secret files, never checked in; encryption primary key file may list several keys during rotation |
| PASSWORD_HASH_ALGORITHM | argon2id (bcrypt only if the pinned Rails lacks Argon2 support) |
| ARGON2_MEMORY_KIB / ARGON2_ITERATIONS / ARGON2_PARALLELISM | 19456 / 2 / 1 minimum; tuned by benchmark |
| BCRYPT_COST | 12 (only when bcrypt is in use) |
| FFMPEG_BASE_URL | http://ffmpeg:8080 |
| FFMPEG_API_KEY_FILE | Worker-only secret |
| PROXY_NETWORK / DATABASE_NETWORK / MEDIA_NETWORK | Existing operator-managed network names |
| WEB_CONCURRENCY / RAILS_MAX_THREADS (web) | 1 / 3 |
| WEB_CONCURRENCY / RAILS_MAX_THREADS (media) | 1 / 5 |
| PUBLISH_CONCURRENCY | 2 |
| MAX_UPLOAD_BYTES | 268435456, aligned with processor |
| MEDIA_CHUNK_BYTES | 2097152 |
| MAX_UPLOADS_PER_USER | 2 |
| MAX_RANGE_RESPONSE_BYTES | 8388608 |
| WORKSPACE_MEDIA_QUOTA_BYTES | Operator-set; required |
| DISPATCH_INTERVAL_SECONDS | 15 |
| MISSED_SCHEDULE_GRACE_SECONDS | 900 |
| PROVIDER_PENDING_TIMEOUT_SECONDS | 3600 |
| PROVIDER_BUDGETS | Owner-set monthly spend limits per paid provider (for example X); unset blocks paid publishing |
| TRACKED_LINKS_ENABLED | true when `PUBLIC_BASE_URL` is reachable from the internet; false disables tracked links |
| LINK_DIGEST_SECRET_ROTATION | Daily; previous secret deleted after 48 hours (09, Privacy) |
| STORE_POLL_MINUTES | 15 |
| FX_RATE_SOURCE | ECB daily reference rates (worker outbound) |
| RELAY_ALLOWED_HOSTS | Allowlisted relay base URLs (YAGPDB fork, Telegram bot) |
| RELAY_MEDIA_GRANT_SECONDS | 3600 |
| DEFAULT_TIMEZONE | America/Toronto |

If media routes run in the web role instead of a separate media role, use at least 5 threads there.

Start with separate measured memory budgets for web, media and worker, approximately 512–768 MiB each as a sizing hypothesis; the media role's tmpfs counts toward its allowance. Account for Ruby baseline, threads and streaming clients. Configure each pool for all job/framework threads and set a deployment-wide connection budget within the existing PostgreSQL server's spare capacity. Queue and app tables initially share one database with separate table namespaces.

Health: web and media liveness check their process, readiness checks DB/schema. Worker heartbeat exposes a DB timestamp for monitoring. FFmpeg outage blocks media work, not text-only publishing. Deployment runs migrations once with a DDL-capable role; runtime roles cannot migrate. Back up PostgreSQL plus encryption keys separately and test restore, including restore time at the expected media volume.

### Rollback compatibility

A deployment is rollback-compatible only if the previous release can read everything the new release writes. Schema, checkpoint and plugin-state format changes therefore ship in two steps: first a release that reads both old and new formats while still writing the old one, then a release that writes the new format. Checkpoints and plugin records carry a schema version; code that meets a newer version than it understands stops the affected target as `needs_attention` instead of guessing.

## Acceptance criteria

- One post targets three services at independent times and retains separate receipts.
- Editing one platform's copy of a queued post changes only that target's revision and content; its slot and its siblings are unchanged.
- Queue drag, pause, resume, DST and concurrent reorder produce no duplicate slot-occurrence claims.
- Duplicate dispatch and crash-after-send tests do not blindly repeat publication.
- A target delayed less than the grace window publishes; one delayed beyond it follows the missed-schedule rule.
- Source/result streaming stays bounded as input size grows. No whole media file is written to Rails disk; transient request buffers never exceed one chunk per thread and live only on memory-backed tmpfs.
- Interrupted uploads resume from the last stored chunk.
- Unvalidated uploads are never served to browsers; validated previews use server-assigned types.
- User passwords are stored only as salted Argon2id (or bcrypt fallback) hashes; a login with an outdated hash re-hashes it; the database rejects any `password_digest` that is not a recognized hash string.
- Provider credentials and app passwords are unreadable in a database dump without the key files, and survive a full key rotation.
- Concurrent credential refresh for one account performs one provider call; a crash after rotation leads to reconnect, not a loop.
- Existing PostgreSQL is reused without volume or server changes.
- Workspace separation, expired media links, OAuth rotation and plugin disable tests pass.
- Migration, rollback-compatible deployment and backup restore are documented and exercised.

## References

- [Rails Active Job](https://guides.rubyonrails.org/active_job_basics.html) and [Solid Queue](https://github.com/rails/solid_queue) — job backend.
- [Rails security](https://guides.rubyonrails.org/security.html) and [encryption](https://guides.rubyonrails.org/active_record_encryption.html).
- [PostgreSQL limits](https://www.postgresql.org/docs/current/limits.html) — field size motivates chunking.
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) — hashing algorithms and parameters.
- [has_secure_password](https://api.rubyonrails.org/classes/ActiveModel/SecurePassword/ClassMethods.html) and [Argon2 support in Rails](https://rubyonrails.org/2025/11/7/this-week-in-rails).
- [atproto SDK authentication](https://atproto.com/guides/sdk-auth) — app passwords versus OAuth.
- [PostgreSQL TOAST](https://www.postgresql.org/docs/current/storage-toast.html) — column storage strategies.

Scheduling semantics, data model and defaults are project decisions.

## Changes in 1.2

- Integrations moved to addon sheets 02-1 to 02-10; added itch.io and Jinxxy store addons, Discord through a self-hosted YAGPDB fork and a Telegram bot relay.
- Added tracked-link redirects, relay API and media grants, metrics polling, store imports and attribution jobs to the roles; YAGPDB and Telegram bot in the topology; new configuration.
- Made per-platform editing of targets explicit.

## Changes in 1.1

- Replaced single-request streaming uploads with a resumable chunked upload protocol; Puma buffers large bodies to disk.
- Added an optional media role and range-response cap so media traffic cannot starve the UI.
- Unvalidated uploads are no longer served; previews use server-assigned types, nosniff and sandbox CSP.
- Added `PUBLIC_MEDIA_BASE_URL`; fetch-by-URL is disabled when media is not publicly reachable.
- Credential refresh now uses a lease row and compare-and-swap instead of a lock held across HTTP.
- Added `credential_refresh_leases`, `webhook_endpoints`, `upload_sessions`, `plugin_checkpoints`, `remote_media_handles`, `attention_reason`, `next_poll_at` and slot-occurrence uniqueness.
- Added `awaiting_provider` state for provider-side processing.
- Defined a missed-schedule grace window and dispatcher interval.
- Set EXTERNAL storage on media chunks, added media quotas and storage operations guidance.
- Worker cleans up orphaned remote processing jobs.
- Set the v1 provider set to Instagram, TikTok, YouTube, X, Bluesky and Mastodon; LinkedIn removed from examples. Added `plugin_app_registrations`, `provider_throttles`, `provider_usage` and `PROVIDER_BUDGETS`.
- Added the declared-protection rule for images (07_Media_Protection_Specification.md).
- Added Credential storage: OWASP-aligned salted Argon2id password hashing (bcrypt fallback), rehash on login, encryption for provider credentials and Bluesky app passwords, key rotation, and digest-only lookup tokens.
- Data model table now defers to 08_Database_Schema_Specification.md; added `unsupported_checkpoint_version` attention reason.
- Corrected retry wording (Active Job, not Solid Queue) and defined two-step format changes for rollback compatibility.
