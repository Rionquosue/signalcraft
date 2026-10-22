# 2 - 3 YouTube Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `youtube` • kind `social`

Provider facts are from Google's public documentation as of October 2026 and are re-verified at implementation. The addon contract is in 04; host behavior is in 02 and 09.

## Requirements

- A Google Cloud project with the YouTube Data API v3 and YouTube Analytics API enabled, OAuth consent configured (`credentials_source: operator_config`).
- The upload allowance belongs to the Google project, so every connected YouTube account in the deployment shares it.

## Manifest

```yaml
id: youtube
kind: social
name: YouTube
plugin_api: ">=1.2 <2.0"
auth:
  strategy: oauth2_pkce
  scopes:
    - https://www.googleapis.com/auth/youtube.upload
    - https://www.googleapis.com/auth/youtube.readonly
    - https://www.googleapis.com/auth/yt-analytics.readonly
capabilities:
  text: false
  images: false
  video: true
  audio: false
  alt_text: false
  requires_media: true
  media_fetch_by_url: false
  remote_idempotency: false
  reconciliation: true
  link_placement: in_post          # links in the description are clickable
  metrics: [views, likes, replies, avg_watch_seconds, total_watch_seconds]
settings:
  - key: privacy_status
    type: enum
    values: [public, unlisted, private]
    default: public
  - key: title
    type: string
    help: "Video title; defaults to the first line of the post text"
```

## Publishing

| Step | Behavior |
|---|---|
| Content | Post text becomes the description; the title comes from the `title` setting or the first line of text. |
| Upload | `videos.insert` with a resumable upload session streamed from `media.open`. The session URI and confirmed byte offset are saved as checkpoints so an interrupted upload resumes rather than restarts. |
| Quota | `videos.insert` is limited per project per day (100 calls per day per the method's documentation at the time of review). Report quota exhaustion as `RateLimited` with scope `provider_app`; the composer shows remaining daily uploads when low (05). |
| Processing | After upload YouTube processes the video; the video ID is returned at upload completion, so the target is `published`. Processing status is shown in history but does not change the target state. |
| Unverified projects | Videos from unverified projects are not restricted to private viewing, according to the method documentation reviewed. |

## Links

Description links are clickable: `link_placement: in_post`, and tracked links are substituted into the description.

## Metrics

Through the YouTube Analytics API, per video:

| Normalized key | Analytics metric |
|---|---|
| views | `views` |
| likes | `likes` |
| replies | `comments` |
| avg_watch_seconds | `averageViewDuration` |
| total_watch_seconds | `estimatedMinutesWatched` × 60 |

Thumbnail impressions are available only through the bulk Reporting API (`video_thumbnail_impressions`) and are not collected in v1.

## Errors

| Provider condition | Normalized error |
|---|---|
| `quotaExceeded` | RateLimited (provider_app), retry after the daily reset |
| Upload session lost | TransientFailure (`not_submitted`) if no bytes were committed; otherwise resume from the saved offset |
| Upload completed but response lost | UnknownOutcome; reconcile by listing the channel's recent uploads for a matching title and upload time |
| Invalid or revoked grant | ReauthorizationRequired |

## Addon-specific tests

Resumable upload interruption and resume, quota exhaustion shared across two accounts, reconciliation after a lost completion response, title fallback and metric mapping including the minutes-to-seconds conversion.

## Verify at implementation

Current daily upload limits and quota costs, and whether Analytics API values lag (typically data is not real-time).

## References

- [YouTube videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert)
- [YouTube reporting metrics](https://developers.google.com/youtube/reporting/v1/reports/metrics)
