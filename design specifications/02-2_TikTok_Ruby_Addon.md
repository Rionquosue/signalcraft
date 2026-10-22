# 2 - 2 TikTok Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `tiktok` • kind `social`

Provider facts are from TikTok for Developers documentation as of October 2026 and are re-verified at implementation. The addon contract is in 04; host behavior is in 02 and 09.

## Requirements

- A TikTok developer app with the Content Posting API product, Direct Post enabled and the `video.publish` scope approved; `video.list` for metrics.
- Until TikTok audits the app, everything it posts is restricted to private viewing. The addon reports this as an account capability (`audited: false`), and the composer fixes visibility to private with an explanation.

## Manifest

```yaml
id: tiktok
kind: social
name: TikTok
plugin_api: ">=1.2 <2.0"
auth:
  strategy: oauth2_pkce
  scopes: [user.info.basic, video.publish, video.list]
capabilities:
  text: false
  images: true          # photo posts
  video: true
  audio: false
  alt_text: false
  requires_media: true
  media_fetch_by_url: false
  remote_idempotency: false
  reconciliation: true
  link_placement: profile_only
  metrics: [views, likes, replies, shares]
settings:
  - key: privacy_level
    type: enum
    values_from: creator_info     # options fetched per creator
  - key: allow_comments
    type: boolean
```

## Publishing

| Step | Behavior |
|---|---|
| Creator info | Before every post, query creator info (`/v2/post/publish/creator_info/query/`) and validate privacy level and comment, duet and stitch settings against what the creator currently allows. |
| Video limits | MP4 (preferred), WebM or MOV; H.264 preferred; 23–60 fps; 360–4096 px per side; up to 10 minutes and 4 GB through the upload endpoint. The host's processor caps uploads at 256 MiB and 600 seconds, which is within these limits. |
| Photos | WebP or JPEG, up to 1080p and 20 MB each; confirm the photo transfer method at implementation. |
| Upload | `FILE_UPLOAD`: initialize, then upload sequential chunks from `media.open`. Files under 5 MB go in one chunk; otherwise chunks are 5–64 MB, the last up to 128 MB, at most 1,000 chunks, each with `Content-Range`. A 403 means the upload URL expired: start a new upload. The upload URL and offsets are saved as a checkpoint. `PULL_FROM_URL` is not used (it needs a verified domain). |
| Status | After initialization, poll the publish status and return `pending` until TikTok reports the post complete or failed. |

## Links

Captions are not clickable: `link_placement: profile_only`. The composer offers the account's tracked profile link.

## Metrics

From the video object (`video.list` scope):

| Normalized key | TikTok field |
|---|---|
| views | `view_count` |
| likes | `like_count` |
| replies | `comment_count` |
| shares | `share_count` |

Watch time and reach are not available through this API.

## Errors

| Provider condition | Normalized error |
|---|---|
| Creator settings disallow the chosen privacy or interactions | ValidationError on the matching field |
| Upload URL expired (403) | TransientFailure (`not_submitted`) with a fresh upload |
| Token expired | AuthenticationExpired |
| Spam or posting-frequency limits | RateLimited (account) |

## Addon-specific tests

Creator-info validation, unaudited private-only behavior, chunk size computation at the boundaries (5 MB, 64 MB, final chunk), upload URL expiry, publish status polling, and metric field mapping.

## Verify at implementation

Publish status endpoint and states, photo-post transfer methods, rate limits (not stated in the documentation reviewed) and the current audit process.

## References

- [TikTok media transfer guide](https://developers.tiktok.com/doc/content-posting-api-media-transfer-guide)
- [Content Posting API: getting started](https://developers.tiktok.com/doc/content-posting-api-get-started)
- [TikTok video object](https://developers.tiktok.com/doc/tiktok-api-v2-video-object)
