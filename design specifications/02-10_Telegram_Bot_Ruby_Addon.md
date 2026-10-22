# 2 - 10 Telegram bot Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `telegram_bot` • kind `social` • relay protocol 1.0 (push or pull)

## Purpose and scope

Post scheduled news to Telegram channels or groups through a Telegram bot you will build separately. This sheet defines only how that bot interacts with the Rails application: the API calls, the data exchanged and the rules both sides follow. How the bot itself is written, hosted and configured is up to its own project.

The interaction is the relay protocol in 10_Relay_Bot_Protocol_Specification.md. This sheet adds the Telegram-specific parts.

## Roles

| Side | Responsibilities |
|---|---|
| Rails (`telegram_bot` addon) | Scheduling, queues, content and per-platform overrides, media variants within the bot's limits, tracked links, retries and reconciliation, history |
| Your bot | Holding the Telegram bot token, posting to chats, reporting each destination's limits and status, reporting delivery results, never posting a delivery twice |

Rails never sees the Telegram bot token. The bot never sees social credentials or other destinations.

## Destinations

One destination is one Telegram chat the bot can post to: a channel (`@name` or `-100…` ID) or a group. Each destination is one social account in Rails, with its own queue, schedule and Insights row.

The bot assigns each destination an ID (`dst_` plus random characters) and reports, through the protocol:

| Field | Telegram meaning |
|---|---|
| `kind` | `telegram_channel` or `telegram_group` |
| `display_name` | Chat title |
| `container_name` | Public username if any |
| `can_post` / `problem` | Whether the bot is a member with permission to post; problems: `bot_removed`, `missing_permission`, `chat_not_found` |
| `limits` | As below |
| `options` | Subset of `silent`, `suppress_link_previews`, `delete_message` |

## Limits the bot reports

Defaults reflect the Telegram Bot API as generally documented; the bot must report the values it actually enforces, and both should be re-checked against the current Bot API when the bot is built.

| Limit | Default | Telegram basis |
|---|---|---|
| max_text_chars | 4096 | Text message length |
| max_caption_chars (extension field) | 1024 | Caption length when media is attached |
| max_attachments | 10 | Media group size |
| max_attachment_bytes | 52428800 | Bot uploads (50 MB); photos have a lower limit (10 MB), reported as `max_photo_bytes` |
| media_types | JPEG, PNG, WebP, GIF, MP4 | |

When a post has media and text longer than the caption limit, the bot sends the media first and the text as a following message, and reports both message IDs. Rails warns about this in the composer (05).

## Choosing a mode

| Mode | When | What the bot must offer |
|---|---|---|
| Pull (recommended for Telegram) | The bot uses long polling to Telegram and has no inbound HTTP endpoint | An HTTPS client that calls Rails; configuration for the Rails URL and pull token |
| Push | The bot runs an HTTPS server Rails can reach | The relay endpoints from sheet 10 and a relay token issued to Rails |

### Pull mode sequence

1. In Rails, an owner chooses Accounts → Connect → Telegram bot → Pull. Rails creates a link and shows a pull token once.
2. The owner adds the Rails relay URL (`/integrations/telegram_bot/relay/v1`) and token to the bot's configuration.
3. For each chat, the bot calls `PUT /destinations/{destination_id}` with its status and limits. Rails lists unclaimed destinations for the owner to confirm; confirming creates the social account.
4. The bot loops on `GET /deliveries?limit=20` (long poll, up to 25 seconds).
5. For each delivery: fetch media from `fetch_url`, verify size and SHA-256, post to Telegram (`sendMessage`, `sendPhoto`, `sendVideo` or `sendMediaGroup`), then `POST /deliveries/{key}/result`. Call `/extend` while large uploads run past half the lease.
6. The bot refreshes each destination with `PUT /destinations/{id}` at least daily and whenever its permissions change.

### Push mode sequence

1. The bot generates a relay token and shows it once.
2. In Rails, the owner chooses Connect → Telegram bot → Push and enters the bot's relay URL, destination ID and relay token. Rails calls `GET /destinations/{id}`.
3. Rails POSTs deliveries when they are due and polls `GET /deliveries/{key}`.

## Message rules for the bot

- Post `text` exactly as given, as plain text: no `parse_mode`. Links are already final (tracked links substituted) and must not be shortened or rewritten.
- Alt text has no Telegram field; the bot ignores it.
- `silent` maps to Telegram's silent-notification option; `suppress_link_previews` to disabling the link preview.
- Never post a delivery whose idempotency key it has already handled; keep keys and results for at least 14 days, persisted across restarts.
- If Telegram's response is lost after a send request (timeout, crash), report `unknown` with `delivery_state: unknown`. Rails then asks a person to check, rather than reposting.
- Telegram rate-limit responses (retry-after) are handled inside the bot for up to 2 minutes; beyond that, report `failed` with `retryable: true` and `delivery_state: not_submitted` so Rails reschedules.
- `message_url`: `https://t.me/{username}/{message_id}` for public channels; omitted for private chats.

## Ruby addon manifest

```yaml
id: telegram_bot
kind: social
name: Telegram (your bot)
plugin_api: ">=1.2 <2.0"
auth:
  strategy: relay_token            # push: relay token from the bot; pull: Rails-issued pull token
capabilities:
  text: true
  images: true
  video: true
  audio: false
  alt_text: false
  requires_media: false
  media_fetch_by_url: false
  remote_idempotency: true
  reconciliation: true
  link_placement: in_post
  metrics: []
settings:
  - key: silent
    type: boolean
  - key: suppress_link_previews
    type: boolean
```

## Media access

`fetch_url` points to Rails's relay media route and works without a public media origin when the bot can reach Rails privately. In pull mode the bot already reaches Rails, so media fetches use the same route. Each URL is valid for one delivery and expires after 1 hour.

## Metrics

None in v1: the Telegram Bot API does not give bots view counts for posts. Tracked-link clicks still appear in Insights. If the bot later reports reaction counts, that needs a protocol extension (a new optional `metrics` endpoint), not a change to this version.

## Acceptance tests for the bot

The bot passes the relay conformance suite in sheet 10 in its chosen mode, plus:

- A post with media and 3,000 characters of text produces media plus a follow-up text message, and both IDs are reported.
- Removing the bot from a channel makes the next destination report `can_post: false, problem: bot_removed`.
- Killing the bot during a send results in `unknown` for that delivery after restart, and no second post.

## References

- 10_Relay_Bot_Protocol_Specification.md
- [Telegram Bot API](https://core.telegram.org/bots/api) (re-verify limits when building the bot)
