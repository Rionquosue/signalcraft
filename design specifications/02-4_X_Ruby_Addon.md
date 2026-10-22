# 2 - 4 X Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `x` • kind `social`

Provider facts are from X's public documentation and third-party pricing summaries as of October 2026 and are re-verified at implementation. The addon contract is in 04; host behavior is in 02 and 09.

## Requirements

- An X developer account with pay-per-use credits (new developers no longer get a free tier, according to the pricing summary reviewed). The operator registers the app (`credentials_source: operator_config`).
- An owner-set monthly budget in `PROVIDER_BUDGETS`. With no budget set, X publishing is blocked (02).

## Manifest

```yaml
id: x
kind: social
name: X
plugin_api: ">=1.2 <2.0"
auth:
  strategy: oauth2_pkce
  scopes: [tweet.read, tweet.write, users.read, media.write, offline.access]
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
  metrics: [impressions, views, likes, replies, reposts, quotes, saves, link_clicks]
  metrics_max_age_days: 30        # for non-public metrics; public metrics continue
```

## Publishing

| Step | Behavior |
|---|---|
| Media | Up to 4 images (5 MB each: JPG, PNG, GIF, WebP), 1 animated GIF (15 MB) or 1 video. Video limits depend on the posting account's tier (default accounts: 20 minutes, 8 GB), so capabilities are fetched per account. The host's 256 MiB, 600-second processor caps apply first. |
| Upload | Simple upload for images; chunked upload (initialize, append, finalize, then status) for GIFs and video, streamed from `media.open`, with the media ID saved in a checkpoint. A video can upload successfully and still be rejected when attached, so attachment errors are validation errors. |
| Post | `POST /2/tweets` with text and media IDs. |
| Cost | Each post costs credits; a post containing a link costs more ($0.015 versus $0.20 per post in the summary reviewed). Before submission the host reserves the estimated cost against the budget (08, provider_usage). The composer shows "Uses paid API credits" and the higher link price (05). |
| Lost response | A timeout after sending is UnknownOutcome; reconciliation looks up the account's recent posts for matching text. |

## Links

Links are clickable: `link_placement: in_post`. Because links raise the price per post, the composer states the cost difference when a tracked link is added.

## Metrics

| Normalized key | X field | Notes |
|---|---|---|
| impressions | `public_metrics.impression_count` | |
| views | media `public_metrics.view_count` | Video posts only |
| likes | `like_count` | |
| replies | `reply_count` | |
| reposts | `retweet_count` | |
| quotes | `quote_count` | |
| saves | `bookmark_count` | |
| link_clicks | `non_public_metrics.url_link_clicks` | Needs user context; only for posts from the last 30 days |

- Reads are billed (about $0.005 per post read in the summary reviewed). Each poll reports `cost_micros`, which counts toward the budget and the account's costs in Insights. The default schedule polls X only at 24 hours and 7 days (09).
- Video playback quartiles (`playback_0_count` to `playback_100_count`) exist but are not mapped in v1.
- Up to 100 posts are fetched per request.

## Errors

| Provider condition | Normalized error |
|---|---|
| 429 with reset header | RateLimited (account or provider_app, per header) |
| 403 for video longer than the account allows | ValidationError on the video |
| Budget would be exceeded | Blocked before submission (`budget_exhausted`), not an addon error |
| Invalid token | AuthenticationExpired, then ReauthorizationRequired |

## Addon-specific tests

Cost reservation and release, link-price estimate, chunked upload resume, attachment rejection after successful upload, reconciliation after a lost response, 30-day cutoff for non-public metrics and read-cost reporting.

## Verify at implementation

Current pricing for posts, posts with links and reads, current scopes for media upload, and rate limits for the pay-per-use tier. Confirm prices in the X developer console, since the figures above come from a vendor summary.

## References

- [X media upload](https://docs.x.com/x-api/media/introduction)
- [X API metrics](https://docs.x.com/x-api/fundamentals/metrics)
- [X API pricing summary (Postproxy)](https://postproxy.dev/blog/x-api-pricing-2026)
