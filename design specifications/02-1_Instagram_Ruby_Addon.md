# 2 - 1 Instagram Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `instagram` • kind `social`

Provider facts are from Meta's public documentation as of October 2026 and are re-verified at implementation. The addon contract is in 04; host behavior is in 02 and 09.

## Requirements

- An Instagram professional account connected to a Facebook Page. If the Page requires Page Publishing Authorization, publishing is blocked until it is completed.
- `PUBLIC_MEDIA_BASE_URL` reachable from the internet: Instagram only accepts media it fetches from a public URL. Without it, Instagram accounts show "Not available on this server".
- A Meta app registered by the operator (`credentials_source: operator_config`).

## Manifest

```yaml
id: instagram
kind: social
name: Instagram
plugin_api: ">=1.2 <2.0"
auth:
  strategy: oauth2
  scopes: [instagram_business_basic, instagram_business_content_publish, instagram_business_manage_insights]
capabilities:
  text: false
  images: true
  video: true
  audio: false
  alt_text: true
  requires_media: true
  media_fetch_by_url: true
  remote_idempotency: false
  reconciliation: true
  link_placement: profile_only
  metrics: [views, reach, likes, replies, shares, saves, avg_watch_seconds, total_watch_seconds]
  metrics_max_age_days: 730
settings:
  - key: media_type
    type: enum
    values: [feed, reel, story, carousel]
    default: feed
```

Scopes shown are for Instagram Login; with Facebook Login the equivalents are `instagram_basic`, `instagram_content_publish`, `instagram_manage_insights` and `pages_read_engagement`.

## Publishing

| Step | Behavior |
|---|---|
| Media | Images must be JPEG; the host produces JPEG variants through FFmpeg. Carousels hold up to 20 items and are cropped to the first item's aspect ratio. |
| Container | `prepare_media` creates a media container with a signed `image_url` or `video_url` from `media.signed_url`, saving the container ID in a checkpoint immediately. |
| Status | Container status is polled (`IN_PROGRESS`, `FINISHED`, `ERROR`, `EXPIRED`) about once a minute by returning `pending` with `next_poll_at`; containers expire after 24 hours. |
| Publish | `media_publish` with the finished container. If the response carries no media ID, return `unknown` and reconcile through container status. |
| Limit | 100 API-published posts per account per rolling 24 hours (Meta's page also mentions 50 for carousels; the lower value is assumed until verified). Usage is checked with `content_publishing_limit` before submission; at the limit, return `RateLimited` with account scope. |
| Declared-protected images | Must already be JPEG within limits; otherwise blocked with `protected_media_incompatible` (07). |

## Links

Captions are not clickable, so `link_placement: profile_only`. The composer offers the account's tracked profile link for the bio instead of putting a link in the caption (09).

## Metrics

| Normalized key | Instagram metric | Applies to |
|---|---|---|
| views | `views` | Feed, reels, stories |
| reach | `reach` | Feed, reels, stories |
| likes | `likes` | Feed, reels |
| replies | `comments` | Feed, reels |
| shares | `shares` | Feed, reels, stories |
| saves | `saved` | Feed, reels |
| avg_watch_seconds | `ig_reels_avg_watch_time` (milliseconds, converted) | Reels |
| total_watch_seconds | `ig_reels_video_view_total_time` (milliseconds, converted) | Reels |

- `impressions` is deprecated for media created after 2 July 2024 and is not used.
- Data can lag up to 48 hours; stored for up to 2 years. Story metrics disappear after 24 hours, so stories use the 1-hour and 20-hour schedule (09).
- Carousel (album) children have no insights; the carousel as a whole is measured.

## Errors

| Provider condition | Normalized error |
|---|---|
| Publishing limit reached | RateLimited (account) |
| Container `ERROR` | PermanentFailure with the container's sanitized status |
| Container `EXPIRED` before publish | TransientFailure (`not_submitted`): a new container is created |
| Token expired or permission revoked | AuthenticationExpired / ReauthorizationRequired |
| Page Publishing Authorization required | ReauthorizationRequired with an explanation |

## Addon-specific tests

JPEG-only enforcement, container polling to finished and to expired, missing media ID followed by reconciliation, publishing-limit handling, story metric schedule, millisecond conversion of watch time, and refusal when no public media origin is configured.

## Verify at implementation

The 50 versus 100 daily limit, current insights metric names (several are marked "in development"), and whether text-only posts remain unsupported.

## References

- [Instagram content publishing](https://developers.facebook.com/docs/instagram-platform/content-publishing)
- [Instagram media insights](https://developers.facebook.com/docs/instagram-platform/reference/instagram-media/insights/)
