# Rails addon (plugin) API — specification sheet

Contract 1.2 • 22 October 2026 • Proposed Ruby extension interface

## Scope and trust

Each external service is a versioned Ruby gem, called an addon (the code and data model also call it a plugin; the terms are interchangeable). There are two kinds:

| Kind | Interface | Purpose |
|---|---|---|
| `social` | SocialPublisher::PluginV1 | Connect a social account, publish to it and read post metrics |
| `commerce` | SocialPublisher::CommercePluginV1 | Connect a storefront and import products and orders for revenue attribution |

The host owns users, secrets, queues, scheduling, retries, database media, tracked links, attribution and UI. Addons translate provider-specific authentication, publishing, metrics and order data.

Each addon has its own specification sheet, numbered under the Rails application (sheet 02):

| Sheet | Addon | plugin_id | Kind |
|---|---|---|---|
| 02-1_Instagram_Ruby_Addon.md | 2 - 1 Instagram | `instagram` | social |
| 02-2_TikTok_Ruby_Addon.md | 2 - 2 TikTok | `tiktok` | social |
| 02-3_YouTube_Ruby_Addon.md | 2 - 3 YouTube | `youtube` | social |
| 02-4_X_Ruby_Addon.md | 2 - 4 X | `x` | social |
| 02-5_Bluesky_Ruby_Addon.md | 2 - 5 Bluesky | `bluesky` | social |
| 02-6_Mastodon_Ruby_Addon.md | 2 - 6 Mastodon | `mastodon` | social |
| 02-7_itch_io_Ruby_Addon.md | 2 - 7 itch.io | `itch_io` | commerce |
| 02-8_Jinxxy_Ruby_Addon.md | 2 - 8 Jinxxy | `jinxxy` | commerce |
| 02-9_Discord_YAGPDB_Ruby_Addon.md | 2 - 9 Discord (self-hosted YAGPDB) | `discord_yagpdb` | social, relay |
| 02-10_Telegram_Bot_Ruby_Addon.md | 2 - 10 Telegram (your bot) | `telegram_bot` | social, relay |

Relay addons (02-9, 02-10) publish through a bot you run instead of a platform API; the HTTP contract between Rails and those bots is 10_Relay_Bot_Protocol_Specification.md. Both use a shared host relay base, so the addon code is mainly limits and options. Their auth strategy is `relay_token`.

LinkedIn and other providers are out of scope for v1. Addon sheets record each provider's public documentation as of October 2026 and list what must be re-verified at implementation; at runtime an addon's reported capabilities, not its sheet, are authoritative.

This is an in-process Ruby interface, not a public REST API and not a sandbox. An addon has the application's process privileges. Install only reviewed, pinned gems in the application image. Namespace isolation or a Rails engine does not protect credentials from malicious code. Untrusted third-party addons would require a separate out-of-process architecture, outside v1.

No core source changes should be needed to add a conforming addon. Installation changes the dependency lockfile, registered manifest and deployment image. Owners enable already-installed addons; runtime arbitrary code upload is unavailable.

## Manifest and discovery

```yaml
id: example_social
kind: social                 # social or commerce
name: Example Social
version: 1.0.0
plugin_api: ">=1.2 <2.0"
entrypoint: ExampleSocial::Adapter
config_schema_version: 1
checkpoint_schema_version: 1
auth:
  strategy: oauth2_pkce
  scopes: [profile, publish, metrics]
capabilities:
  text: true
  images: true
  video: false
  audio: false
  alt_text: true
  requires_media: false
  media_fetch_by_url: false
  remote_idempotency: false
  reconciliation: true
  webhooks: false
  delete_remote: false
  link_placement: in_post    # in_post, profile_only or none
  metrics: [likes, replies, reposts]
settings:
  - key: default_visibility
    type: enum
    values: [public, unlisted]
    default: public
```

This is a fictional provider manifest, not a claim about any real API. IDs use [a-z][a-z0-9_]{2,63}. Entrypoints resolve only from the installed registry, never from user input. Duplicate IDs, incompatible API ranges and unknown required manifest fields fail addon loading. Missing optional capabilities default false (or an empty list). The owner dashboard must expose failures, and affected targets become blocked.

`media_fetch_by_url: true` means the provider can only receive media by fetching a URL. When the host has no `PUBLIC_MEDIA_BASE_URL`, it reports media as unsupported for that addon's accounts, with an explanation, instead of failing at publish time.

`link_placement` tells the host where a tracked link can go: `in_post` (a clickable link in the post), `profile_only` (links in captions are not clickable, so the host offers an account-level profile link instead) or `none`.

Declare approved authentication/API/upload hosts and supported configurable-instance rules. Redirect targets and upload endpoints still pass host HTTP-client validation. A manifest host list is an interoperability policy, not a security sandbox for Ruby code.

## Host/addon ownership

| Host owns | Addon owns |
|---|---|
| OAuth state, callback routing, PKCE secret storage | Provider endpoints, scopes and grant translation |
| Encrypted credential persistence and the refresh lease | Credential exchange/refresh logic and normalized results |
| Webhook endpoint tokens, routing and secret storage | Signature verification and event normalization |
| Drafts, per-target scheduling, snapshots, retry decisions | Provider payload mapping and validation |
| Media storage and signed URLs | Upload-session protocol and remote media handles |
| Rate-limit state, execution deadlines, durable checkpoints | Interpretation of provider headers and errors |
| Metrics polling schedule and snapshot storage | Fetching provider metrics and mapping them to normalized keys |
| Tracked links, click logging, attribution and profit estimates | Importing products and orders and describing store fees |
| UI rendering and workspace authorization | Declarative fields and human-readable constraints |

Addons must not create their own schedulers, modify queue tables, query unrelated workspaces, log credentials, store buyer personal data or invoke FFmpeg. Use host services by contract; code review and tests enforce these rules for trusted addons.

## Social addon method contract

All values are typed DTOs or plain validated JSON-compatible data. Implementations are stateless across calls; no reliance on process memory. Context objects are per invocation, never global.

| Method | Input → output | Requirement |
|---|---|---|
| manifest | none → Manifest | Required |
| capabilities | account context → Capabilities | Required; may vary by account and provider API version |
| authorization_request | context, callback_url, state, pkce_challenge → AuthorizationRequest | Required for interactive auth |
| exchange_authorization | context, callback_payload, callback_url, pkce_verifier → CredentialSet | Required for selected auth strategy |
| refresh_credentials | context → CredentialSet | Required if credentials expire and are renewable |
| account_identity | context → AccountIdentity | Required |
| validate | context, TargetSnapshot → ValidationResult | Required, no publishing side effects |
| prepare_media | context, MediaInput, checkpoint → MediaResult | Required if media supported |
| publish | context, TargetSnapshot, media_handles, idempotency_key, checkpoint → PublishResult | Required |
| reconcile | context, PublishReceipt → ReconcileResult | Required when capability true, or when publish can return pending |
| fetch_metrics | context, published_posts[] → MetricsResult | Required when `metrics` is non-empty |
| revoke_credentials | context → RevocationResult | Optional |
| delete_remote | context, remote_post_id → DeleteResult | Optional; explicit user action only |
| verify_webhook | raw_body, headers, webhook_secret, now → VerifiedEvent or Rejected | Required if webhooks supported |
| migrate_state | old_schema_version, state → new state | Required when stored schema changes |

Unsupported optional methods return UnsupportedCapability, never a no-op success. OAuth1, API-key and application-password strategies may supply their own declarative credential forms; all secrets enter host-managed encrypted storage.

## Social addon DTO definitions

| Type | Required fields / semantics |
|---|---|
| AccountIdentity | provider_account_id, display_name, handle, profile_url, account_type |
| CredentialSet | secret values, granted_scopes, expires_at nullable, refresh token nullable; encrypted by host immediately |
| Capabilities | supported content/media types, provider-aware text counter, limits, features, supported settings, link_placement, metrics catalog, fetched_at |
| TargetSnapshot | target_id, revision, workspace/account IDs, text (with tracked links already substituted), ordered asset references, alt text, provider_options, immutable content hash |
| ValidationResult | valid, errors[], warnings[], normalized preview data |
| ValidationIssue | code, field, safe_message; field paths map to composer controls |
| MediaInput | asset_id, verified MIME/size/checksum, dimensions/duration, protection_declared and host stream opener |
| MediaResult | ready or pending; remote_handle, expires_at, checkpoint, next_poll_at |
| PublishReceipt | attempt_id, submission_started_at, remote_request_id/post_id if known, checkpoint, idempotency key |
| PublishResult | published, pending or unknown; receipt; next_poll_at when pending; published_at and remote URL only when confirmed |
| ReconcileResult | published, pending, definitively_not_published or unknown; normalized receipt; next_poll_at when pending |
| MetricsResult | per remote_post_id: list of MetricValue; per-post `unavailable_reason` when the provider no longer returns data; optional cost_micros for paid reads |
| MetricValue | key (normalized, below), value (non-negative number), provider_name (the provider's own metric name), as_of (provider's data time if given) |

Remote media handles may be account-bound and expire. The host persists them encrypted in `remote_media_handles` and reuploads expired handles before publishing. A stream opener can reopen at a specified byte offset without creating a local media file. Provider multipart and resumable uploads must preserve bounded memory.

### Result mapping to target state

| Addon result | Target state |
|---|---|
| PublishResult published | published |
| PublishResult pending | awaiting_provider; host calls reconcile at next_poll_at |
| PublishResult unknown or UnknownOutcome | reconcile; if still unknown, needs_attention (publication_unconfirmed) |
| ReconcileResult pending | stays awaiting_provider until the host's pending timeout, then needs_attention (publication_unconfirmed) |
| ReconcileResult definitively_not_published | eligible for retry under the normal retry policy |

### Example publish interface

```ruby
def publish(context:, target:, media_handles:, idempotency_key:, checkpoint:)
  # Use context.http and context.checkpoints.
  # Return a SocialPublisher::PublishResult, or raise a typed error.
end
```

The host calls prepare_media for each asset before publish, resumes pending work through new jobs, and persists every returned checkpoint. Addons must use context.checkpoints.save! for resumable session IDs as soon as obtained. Save submission intent before an irreversible remote request; if a receipt cannot be saved afterward, outcome is unknown.

### Checkpoint and state versioning

Every checkpoint and addon state record carries the addon's schema version. An addon must read its current and previous schema versions. If it meets a newer version than it understands (after a rollback), it raises `UnsupportedCheckpointVersion`; the host then stops the target as `needs_attention` instead of guessing. Format changes ship in two releases: first read both formats while writing the old one, then write the new one.

## Post metrics contract

The host decides when to ask for metrics (09_Insights_and_Attribution_Specification.md); the addon only fetches and maps. Normalized keys:

| Key | Meaning |
|---|---|
| `views` | Times the post or video was viewed or played, as the provider defines it |
| `impressions` | Times the post was shown on screen, as the provider defines it |
| `reach` | Unique accounts that saw the post (provider estimate) |
| `likes` | Likes, favourites or hearts |
| `replies` | Replies or comments |
| `reposts` | Reposts, retweets or boosts |
| `quotes` | Quote posts |
| `shares` | Shares to other surfaces or messages |
| `saves` | Saves or bookmarks |
| `link_clicks` | Link clicks counted by the provider (separate from the host's own tracked-link clicks) |
| `avg_watch_seconds` | Average time spent watching a video |
| `total_watch_seconds` | Total watch time |

Rules:

- `capabilities.metrics` lists only keys the provider actually reports for that account. The UI shows anything missing as "not reported by {provider}", never as zero.
- An addon never derives a key the provider does not report (for example, it never estimates impressions from likes).
- `provider_name` is stored with every value so the UI can show what the number really is (for example Instagram `views` versus X `impression_count`).
- If a provider restricts metrics by age (for example only the last 30 days), the addon declares `metrics_max_age_days` in capabilities and the host stops polling after it.
- Paid reads return `cost_micros`, which the host records against the provider budget and the account's costs.
- `fetch_metrics` accepts up to 100 posts per call; addons batch provider requests where the API allows.

## Commerce addon contract

Commerce addons connect a storefront account. They never publish and have no queues.

| Method | Input → output | Requirement |
|---|---|---|
| manifest | none → Manifest (`kind: commerce`) | Required |
| capabilities | store context → CommerceCapabilities | Required |
| authorization_request / exchange_authorization | as for social addons | Required for OAuth stores |
| account_identity | context → StoreIdentity | Required |
| list_products | context, cursor → ProductPage | Required |
| fetch_orders | context, since, cursor → OrderPage | Required |
| verify_webhook | raw_body, headers, webhook_secret, now → VerifiedOrderEvent or Rejected | Required if `webhooks: true` |
| create_attribution_code | context, product_ids, label, settings → AttributionCode | Optional; only when `attribution_codes` is supported |
| migrate_state | as for social addons | Required when stored schema changes |

| Type | Fields |
|---|---|
| CommerceCapabilities | webhooks, refunds_visible, fees_reported, attribution_codes (none, discount, affiliate), order_history_days, fetched_at |
| StoreIdentity | provider_store_id, display_name, store_url |
| Product | provider_product_id, name, url, currency, list_price_minor, active |
| Order | provider_order_id, ordered_at, status (completed, refunded, partially_refunded), currency, gross_minor, fee_minor (null when not reported), refunded_minor, codes[] (discount or affiliate codes used), items[] |
| OrderItem | provider_product_id, quantity, gross_minor |
| AttributionCode | provider_code_id, code, kind (discount or affiliate), terms summary |

Rules:

- Amounts are integers in the currency's minor unit (cents). Formatted price strings from a provider are parsed by the addon, with currency, and parsing failures are errors, not zeros.
- Orders contain no buyer personal data. If a provider returns email, name, address or license holder details, the addon discards them before returning. Order IDs and product IDs are the only identifiers kept.
- `fetch_orders` is idempotent: the host deduplicates by `(store, provider_order_id)` and updates status and refunds on re-import.
- Store fees not reported by the provider are estimated by the host from the store's fee settings and marked as estimated.

## Context services

| Service | Contract |
|---|---|
| http | TLS verification, host validation, bounded redirects/body, streaming, cancellation and timeouts |
| credentials | Current account's decrypted values, available only for this call; filtered from logs |
| media.open(asset_id, offset:) | Authorized read stream of a validated asset; no host filesystem path |
| media.signed_url(asset_id, expires_in:) | Temporary public URL only when the host has a public media origin; otherwise raises UnsupportedCapability |
| checkpoints.save! | Durable versioned JSON state for this attempt, maximum 64 KiB; encrypted |
| state | Namespaced per-account JSONB, versioned and size-limited (also used for order import cursors) |
| app_registrations | Addon-scoped encrypted client registrations keyed by instance host (for example one Mastodon app per instance); read and create only |
| logger | Redacted structured events, target/attempt correlation |
| clock / cancellation | Injectable UTC clock, deadline and cancellation signal |

Prefer host HTTP deadlines of 5 seconds connect, 30 seconds response and 120 seconds overall per call. Large uploads use bounded streaming and explicit tested overrides. No sleeping through remote processing: return pending with next_poll_at and release the worker.

## Independent schedules and provider limits

The addon receives only a target that the host has made due. Addons must publish immediately or return pending for provider processing; they do not replace the local schedule with provider-native scheduling in v1.

Capabilities govern supported combinations of text, image count, duration, codec, aspect ratio and accessibility metadata. Avoid hard-coding universal character limits in the UI; the addon's counter may account for URLs and Unicode per provider rules. Validate when composing and again just before sending because permissions and capabilities can change.

The host makes account queues independent, including multiple accounts on the same provider. A shared post's successful target remains immutable when another target fails.

Providers that cannot publish text alone declare `requires_media: true`; the composer then disables those accounts for text-only posts with an explanation. Quotas can apply above the account: `RateLimited.scope` is `account`, `provider` or `provider_app`, where `provider_app` means a limit shared by every account using this deployment's API client (for example YouTube's daily upload allowance). The host persists throttles at the stated scope.

Cross-addon rules for the host:

- Media pipelines must stream large single requests (for example TikTok chunks of up to 64 MB and YouTube resumable sessions) from `media.open` without buffering whole chunks in memory.
- Provider-specific variants are produced by the host through the FFmpeg service before `prepare_media`; addons declare the target constraints in capabilities.
- For an image the author declared protected against AI training (see 07_Media_Protection_Specification.md), `prepare_media` receives the original asset with `protection_declared: true` in MediaInput. Addons must upload its bytes unchanged and must not resize or re-encode it; if the provider rejects it, return a ValidationError rather than adapting it.
- Tracked links are substituted into post text by the host before the TargetSnapshot is taken; addons publish the text as given and must not shorten, unwrap or rewrite links.

## Normalized errors and retry policy

| Error class | Host response |
|---|---|
| ValidationError | Block target; surface field errors |
| AuthenticationExpired | One refresh under the account's refresh lease, then retry if safe |
| ReauthorizationRequired | Block account and show reconnect action |
| RateLimited(retry_at, scope) | Persist throttle at account, provider or provider_app scope; reschedule |
| TransientFailure(delivery_state) | Retry only if known not submitted, or provider idempotency guarantees safety |
| PermanentFailure | Mark target failed; require edit/manual action |
| UnknownOutcome(receipt) | Reconcile; never blindly resend |
| UnsupportedCapability | Show unsupported feature; do not silently drop media/content |
| UnsupportedCheckpointVersion | Stop target as needs_attention (reason unsupported_checkpoint_version); surface to owner |

Errors include safe_message, provider_code, retry_at nullable, and delivery_state: not_submitted, submitted or unknown. Transport timeout after bytes may have been sent is unknown. Exceptions must not expose raw credential-bearing provider responses. For metrics and order imports, errors only delay the next poll; they never change a post target's state.

For pre-submission transient errors, default to five retries with capped exponential backoff and jitter. Retry-After takes precedence. A repeated authentication failure ends automatic retries. The stable idempotency key belongs to target revision + publish intent, not each HTTP retry. A new explicit publication creates a new intent.

## Credential refresh

The host calls `refresh_credentials` only while it holds the account's refresh lease, and never inside a database transaction or lock (see 02_Rails_Container_Design.md). The addon performs the provider exchange and returns a CredentialSet; the host persists it with a compare-and-swap on the account's credentials version. Addons must not retry a refresh internally. If the provider rejects a refresh token that may already have been rotated, raise ReauthorizationRequired rather than TransientFailure.

## OAuth, webhooks and lifecycle

Host-generated OAuth state is single-use, session/account-bound and expires after 10 minutes. Validate state before exchange; use PKCE where supported and exact registered callback URLs. Reauthorization must resolve to the intended provider account or require explicit account replacement.

Host routes OAuth at `/integrations/{plugin_id}/callback`. These are application endpoints, distinct from the Ruby addon API.

Webhooks use `/integrations/{plugin_id}/webhooks/{endpoint_token}`. The host issues each endpoint token as at least 128 bits of random data, stores only its hash in `webhook_endpoints`, and binds it to exactly one social account, one store account or one app registration and its webhook secret. On delivery the host:

1. resolves the token by hash; an unknown or inactive token returns 404 without parsing the body, and is rate-limited;
2. loads that endpoint's secret and passes the original raw bytes and relevant headers to `verify_webhook`;
3. on success, deduplicates the normalized provider event ID and queues effects scoped to the endpoint's account or registration.

The destination workspace and account always come from the endpoint token, never from payload fields. When an app-level endpoint serves several accounts, the verified event must name the provider account, and the host only accepts accounts registered under that endpoint. Token rotation creates a new endpoint and keeps the old one active for a configured overlap. Webhook endpoint tokens are filtered from logs.

Installation requires CI contract tests, reviewed dependencies and a pinned artifact. Enable/disable actions are owner-only and audited. Disabling stops new claims; already submitted work is reconciled before removal where possible. Upgrade all web, media and worker roles together, drain active attempts and follow the checkpoint versioning rules above. Removing an addon retains history and blocks scheduled targets. Credential revocation is separate, explicit and best effort.

No arbitrary HTML/JavaScript from addons. Settings use approved boolean, enum, string, integer, decimal and secret field descriptors with labels, help text and validation. Platform icons are bundled sanitized assets. A future inbox (reading replies and messages) needs a separate capability contract.

## Addon certification suite

Provide a host-owned fake HTTP server and shared tests for manifest validation, credentials redaction, OAuth state/PKCE, expired tokens, concurrent refresh under the lease, rejected rotated refresh tokens, media streaming, fetch-by-URL unavailability, unsupported content, limits, retries, duplicate job execution, pending results and polling, crash-after-send reconciliation, webhook replay, unknown and rotated webhook tokens, checkpoint version skew and state migration.

Social addons with metrics additionally test: only declared keys are returned, missing metrics are absent rather than zero, age limits stop polling, and paid reads report cost. Commerce addons additionally test: price parsing per currency, buyer personal data is never returned, re-import is idempotent, refunds update existing orders, and pagination cursors resume after interruption.

Include deterministic fixtures plus opt-in sandbox-provider smoke tests without production accounts. Each addon sheet lists its provider-specific tests.

Adding an example addon must require no changes to host scheduling, media storage, attribution or composer source. Generated fields and capabilities must be enough to connect, draft, queue, publish, inspect history and, where supported, show metrics or import orders.

References: [Rails plugin guide](https://guides.rubyonrails.org/plugins.html), [Rails engines](https://guides.rubyonrails.org/engines.html). Provider references are in each addon sheet. The interface, DTOs and lifecycle rules above are project-defined.

## Changes in 1.2

- Moved all provider-specific content into addon sheets 02-1 to 02-8; added relay addons 02-9 (Discord through a self-hosted YAGPDB fork) and 02-10 (Telegram bot) using the relay protocol in sheet 10.
- Added the `commerce` addon kind for storefronts (itch.io, Jinxxy) with product, order and attribution-code contracts.
- Added the post metrics contract (`fetch_metrics`, normalized metric keys, `metrics` capability).
- Added `link_placement` and the rule that addons publish tracked links unchanged.
- Webhook endpoints may bind to store accounts.

## Changes in 1.1

- Webhooks route through per-endpoint opaque tokens that determine the account and secret; payload fields never select the workspace.
- Credential refresh runs under a host lease with compare-and-swap; plugins raise ReauthorizationRequired for rejected rotated tokens.
- Added a result-to-state mapping, including `awaiting_provider` for pending results.
- Added checkpoint schema versioning, `UnsupportedCheckpointVersion` and two-step format changes.
- Added the `media_fetch_by_url` capability; `signed_url` fails cleanly without a public media origin.
- Defined the v1 provider set (Instagram, TikTok, YouTube, X, Bluesky, Mastodon); LinkedIn is out of scope.
- Added `requires_media`, the `provider_app` rate-limit scope and plugin-scoped `app_registrations`.
- Plugins publish declared-protected images unchanged; MediaInput gains `protection_declared`.
