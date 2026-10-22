# 2 - 6 Mastodon Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `mastodon` • kind `social`

Provider facts are from Mastodon's documentation as of October 2026 and are re-verified at implementation. The addon contract is in 04; host behavior is in 02 and 09.

## Requirements

- One OAuth app registration per Mastodon server, created automatically the first time an account on that server connects and stored in `plugin_app_registrations` (`credentials_source: stored`).
- Private or unusual servers must be allowlisted by the operator (02, outbound HTTP rules).

## Manifest

```yaml
id: mastodon
kind: social
name: Mastodon
plugin_api: ">=1.2 <2.0"
auth:
  strategy: oauth2_pkce
  scopes: [read:statuses, write:statuses, write:media, read:accounts]
capabilities:
  text: true
  images: true
  video: true
  audio: true
  alt_text: true
  requires_media: false
  media_fetch_by_url: false
  remote_idempotency: true          # Mastodon honours an Idempotency-Key header on status creation
  reconciliation: true
  link_placement: in_post
  metrics: [likes, replies, reposts, quotes]
settings:
  - key: visibility
    type: enum
    values: [public, unlisted, private]
    default: public
  - key: content_warning
    type: string
```

## Publishing

| Step | Behavior |
|---|---|
| Limits | Text length and media limits differ per server. Read them from the server's instance configuration (`GET /api/v2/instance`, `configuration.statuses` and `configuration.media_attachments`) and report them as account capabilities. |
| Media | `POST /api/v2/media` with a description (alt text) and optional focus point. Small images return 200 and are ready; larger media returns 202 and is polled with `GET /api/v1/media/:id` (206 while processing, 200 when ready) by returning `pending` from `prepare_media`. |
| Post | `POST /api/v1/statuses` with the target's idempotency key in the `Idempotency-Key` header, so a retried request does not create a second post. |
| Lost response | Retry with the same idempotency key, which returns the original post; otherwise reconcile from the account's recent statuses. |

## Links and preview fetches

Links are clickable: `link_placement: in_post`. Every Mastodon server that receives a post fetches its links to build a preview card, so a single post can cause many automated requests to a tracked link within minutes. These are excluded by the bot filter in 09 (user agents containing `Mastodon/` and the publish-burst rule).

## Metrics

From the Status entity:

| Normalized key | Mastodon field |
|---|---|
| likes | `favourites_count` |
| replies | `replies_count` |
| reposts | `reblogs_count` |
| quotes | `quotes_count` (Mastodon 4.5 and later; omitted on older servers) |

Mastodon does not report views or impressions. Counts are read from the account's own server, which may not know about every interaction on other servers, so they can undercount.

## Errors

| Provider condition | Normalized error |
|---|---|
| 422 validation (text too long, too many media) | ValidationError |
| 429 with `X-RateLimit-Reset` | RateLimited (account) |
| Server unreachable | TransientFailure (`not_submitted`) |
| Token revoked | ReauthorizationRequired |

## Addon-specific tests

Per-server limit discovery, app registration reuse across accounts on the same server, 202 media polling, idempotent status creation, quote count on servers before and after 4.5, and preview-fetch bursts classified as bots.

## Verify at implementation

Idempotency-Key retention period on current Mastodon versions, the quotes feature on target servers, and whether counts on the home server include remote interactions.

## References

- [Mastodon media API](https://docs.joinmastodon.org/methods/media/)
- [Mastodon Status entity](https://docs.joinmastodon.org/entities/Status/)
