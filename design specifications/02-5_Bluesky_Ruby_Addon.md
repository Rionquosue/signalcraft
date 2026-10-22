# 2 - 5 Bluesky Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `bluesky` • kind `social`

Provider facts are from AT Protocol documentation and third-party limit summaries as of October 2026 and are re-verified at implementation. The addon contract is in 04; host behavior is in 02 and 09.

## Requirements

- For atproto OAuth: a client metadata document served at a public HTTPS URL by the Rails application. LAN-only deployments use app passwords instead.
- The account's PDS (personal data server) is configurable; Bluesky-hosted accounts use `bsky.social`. Self-hosted PDSes are reached only if the operator allowlists them.

## Manifest

```yaml
id: bluesky
kind: social
name: Bluesky
plugin_api: ">=1.2 <2.0"
auth:
  strategy: atproto_oauth           # fallback: app_password
capabilities:
  text: true
  images: true
  video: true
  audio: false
  alt_text: true
  requires_media: false
  media_fetch_by_url: false
  remote_idempotency: false
  reconciliation: true
  link_placement: in_post
  metrics: [likes, replies, reposts, quotes]
```

## Authentication

- **atproto OAuth (preferred):** Bluesky recommends OAuth for applications where people sign in.
- **App password (fallback):** the connection form tells the user to create a dedicated app password, never the main password. It is stored encrypted and used only to start a new session when the refresh token has expired; normal publishing uses short-lived session tokens (02, Credential storage).

## Publishing

| Step | Behavior |
|---|---|
| Text | Up to 300 graphemes (and 3,000 bytes). The composer counts graphemes, not characters. |
| Links | Links become clickable only when encoded as rich-text facets with byte offsets; the addon computes facets for every URL in the text, including tracked links. Optionally an external link card is attached for the first link. |
| Images | Up to 4, about 2 MB each; the host produces size-capped variants. Uploaded as blobs to the PDS. |
| Video | 1 per post (limits in the summary reviewed: about 300 MB and 10 minutes, smaller than or equal to the host's processor caps after verification). Uploaded through the video service; processing is polled with `pending`. |
| Post | A `app.bsky.feed.post` record created in the user's repository. The record key returned is the remote post ID. |
| Lost response | Reconcile by listing the account's recent records for matching text and creation time. |
| Rate limits | Bluesky-hosted accounts: 5,000 points per hour and 35,000 per day, with record creation costing 3 points; self-hosted PDSes may differ. |

## Metrics

From the post view returned for the post's URI:

| Normalized key | Bluesky field |
|---|---|
| likes | `likeCount` |
| replies | `replyCount` |
| reposts | `repostCount` |
| quotes | `quoteCount` |

Bluesky does not report views, impressions or reach.

## Errors

| Provider condition | Normalized error |
|---|---|
| Rate limit headers exhausted | RateLimited (account) |
| Blob too large or wrong type | ValidationError on the media |
| Refresh token rejected and no app password stored | ReauthorizationRequired |
| PDS unreachable | TransientFailure (`not_submitted`) |

## Addon-specific tests

Grapheme counting with emoji and combining characters, facet byte offsets for links in multi-byte text, blob size caps, video processing polling, app-password fallback re-establishing a session, and reconciliation after a lost response.

## Verify at implementation

Current image and video limits (from a third-party summary), refresh-token lifetime for app-password sessions, and OAuth client metadata requirements.

## References

- [atproto SDK authentication](https://atproto.com/guides/sdk-auth)
- [Bluesky limits summary (OpenTweet)](https://opentweet.io/answers/bluesky-limits)
