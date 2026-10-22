# Insights and attribution — specification sheet

Specification 1.0 • 22 October 2026 • Proposed implementation contract

## Purpose

Show where effort pays off. Two views share one Insights area:

1. **Revenue by source:** referral clicks from each social platform, account and post to your itch.io and Jinxxy products, with estimated orders, net revenue, costs and profit.
2. **Post performance:** what each platform reports for each published post: views or impressions, reach, likes, replies, reposts, shares, saves and, for video, watch time.

Store data comes from commerce addons (02-7 itch.io, 02-8 Jinxxy). Post metrics come from social addons (02-1 to 02-6). The addon contracts are in 04; tables are in 08.

## Why attribution is estimated

Neither store tells the application which social site a sale came from:

- itch.io's server-side API returns purchases (amount, currency, date) and per-game totals, but no referrer. Referrer reports exist only in the itch.io dashboard.
- Jinxxy's Creator API exposes products, orders and licenses. Its referral and affiliate reporting is a dashboard feature; whether order data includes the code used must be verified (02-8).

The application therefore measures what it can observe directly, clicks on links it issues, and links sales to those clicks by timing. Where an order carries a code issued for one social account, the link is exact.

## Tracked links

| Rule | Detail |
|---|---|
| Creation | When a post includes a store product URL (inserted from the product picker or pasted), the composer offers "Track clicks" (on by default for store links). The host creates one tracked link per post target and destination, so each platform's copy of a post has its own link. |
| Format | `{PUBLIC_BASE_URL}/r/{code}`, where `code` is 10 random base62 characters. |
| Profile links | Platforms whose captions are not clickable (`link_placement: profile_only`, for example Instagram and TikTok) get one tracked link per account and destination, for the profile or bio. Clicks on it are credited to the account, not to individual posts. |
| Destinations | Only product or store URLs from connected stores, or domains an owner has approved. Anything else is published as typed, untracked. This prevents the redirect from being used as an open redirect. |
| Redirect | `GET /r/{code}` logs the click and answers `302` to the destination, adding `utm_source={platform}&utm_medium=social&utm_campaign={post id}` unless the owner disables UTM tags for that store. `HEAD` and unknown codes are not logged. Responses carry `Cache-Control: no-store`. The redirect sets no `Referrer-Policy` stricter than the browser default, so the store can still see the social site where the browser sends it. |
| Reachability | Requires `PUBLIC_BASE_URL` to be reachable from the internet. On LAN-only deployments, tracked links are disabled and links are published as typed. |
| Platform cost | On X, a post containing any link costs more to publish (02-4). The composer shows this before scheduling. |

### Click logging and bot filtering

Every social platform fetches links to build previews, and every Mastodon server that receives a post fetches its links separately. Counting those as clicks would make Mastodon look far better than it is. Each click is therefore classified:

| Signal | Classification |
|---|---|
| User agent matches a known preview fetcher or crawler (for example Twitterbot, facebookexternalhit, Discordbot, TelegramBot, Slackbot, Googlebot, Bluesky's card fetcher, any user agent containing `Mastodon/`) | bot, reason `known_agent` |
| Request does not accept `text/html` | bot, reason `not_browser` |
| More than `BOT_BURST_THRESHOLD` (default 20) distinct visitors within 120 seconds of the post being published | bot, reason `publish_burst`, for that burst |
| Anything else | human |

Only human clicks are used for attribution and click counts. Bot counts are kept so the filter can be checked. The agent list is configuration, updated without a release.

### Privacy

- No cookies, no client-side scripts and no stored IP addresses.
- Unique visitors are counted with a daily digest: HMAC-SHA-256 of IP address and user agent with a secret that changes every day and is deleted after 48 hours. The same person cannot be linked across days, and the digest cannot be reversed to an address.
- Only the referrer's host name is kept (for example `t.co` or `bsky.app`), not the full referring URL.
- Raw click rows are deleted after 90 days; daily totals are kept.
- The owner is responsible for describing link tracking in their privacy notice. This design aims at data minimization under Canadian (PIPEDA) and EU (GDPR) expectations but is not legal advice.

## Orders and profit

Commerce addons import products and orders on a schedule (default every 15 minutes) and through webhooks where the store offers them. Orders carry no buyer personal data.

**Net revenue per order** = gross − refunded − store fees.

- Store fees come from the store when it reports them. Otherwise they are estimated from the store account's fee settings (percentage, fixed amount per order and payment-processing percentage) and marked as estimated. itch.io's revenue share is set by each creator, so it must be entered (02-7).
- Refunds update existing orders when the store reports them. itch.io's API only lists completed purchases, so itch.io refunds are not visible and revenue may be overstated (02-7).
- Amounts are converted to the workspace's reporting currency (default USD) using the daily reference rate for the order date. The default rate source is the European Central Bank's daily reference rates, fetched by the worker. An order without a rate for its date uses the most recent earlier rate, up to 7 days old; beyond that it is excluded from totals and flagged.

**Costs per source:**

| Cost | Source |
|---|---|
| Paid API usage | Recorded automatically per account: X publishing and metric reads (from publish attempts and metric polls) |
| Manual costs | Entered by an owner per account, per platform or for the whole workspace, per month (for example promotion spend or tools) |

Costs not tied to an account or platform are shown separately and not subtracted from any source.

**Estimated profit per source** = attributed net revenue − that source's costs.

## Attribution model

Model version 1. Applied per order line (one product within an order).

1. **Code match (exact).** If the order used an attribution code that the owner linked to a social account (02-8), the whole line is credited to that account. Method `code`.
2. **Click share (estimated).** Otherwise, collect human clicks on tracked links pointing at that product in the attribution window before the order (default 7 days, settable from 1 to 30). Weight each click by age with a half-life (default 48 hours): `weight = 0.5 ^ (age_hours / half_life_hours)`. Each tracked link gets the share of the line equal to its share of total weight. Method `click_share`.
3. **Unattributed.** If no clicks fall in the window, the line is credited to "Unattributed". Method `unattributed`.

Shares for a line always add up to 1. Each allocation records the tracked link, post target (if any), social account, share, allocated net amount and model version.

Known limitations, shown in the method explainer:

- Click share credits social posts for any sale that follows a click, including buyers who would have bought anyway. Totals per platform are therefore upper estimates; comparisons between platforms are more reliable than the absolute numbers.
- Buyers who saw a post but went to the store directly are not counted (they appear as Unattributed).
- Profile-link clicks are credited to the account, not to a specific post.

Attribution is recomputed nightly for orders in the last window plus one day, immediately when late orders or clicks arrive for that period, and for a chosen date range when an owner changes model settings. Recomputing replaces the allocations of that model version for those orders in one transaction.

## Post metrics

### Polling schedule

After a target is published, the worker fetches its metrics at these ages, then stops:

| Default schedule | Ages |
|---|---|
| Most platforms | 1 hour, 6 hours, 24 hours, 3 days, 7 days, 30 days |
| X (paid reads) | 24 hours and 7 days only; owner-configurable |
| Instagram stories | 1 hour and 20 hours (story metrics expire after 24 hours) |

Addons can declare `metrics_max_age_days`; polling never goes past it. Each poll stores one snapshot row per reported metric and records the poll's cost. Polling failures delay that post's next poll; they never change its publish state. Up to 100 posts per account are fetched per call.

### What each platform reports

From each provider's documentation as of October 2026; addon sheets list exact field names and what to re-verify.

| Platform | Views / impressions | Reach | Likes | Replies | Reposts | Quotes | Shares | Saves | Watch time | Link clicks (provider) |
|---|---|---|---|---|---|---|---|---|---|---|
| Instagram | views | yes | yes | yes | — | — | yes | yes | reels average | — |
| TikTok | views | — | yes | yes | — | — | yes | — | — | — |
| YouTube | views | — | yes | yes | — | — | — | — | average and total | — |
| X | impressions; video views | — | yes | yes | yes | yes | — | bookmarks | — | yes, first 30 days |
| Bluesky | — | — | yes | yes | yes | yes | — | — | — | — |
| Mastodon | — | — | favourites | yes | boosts | yes (4.5+) | — | — | — | — |
| Discord (YAGPDB) | — | — | — | — | — | — | — | — | — | — |
| Telegram bot | — | — | — | — | — | — | — | — | — | — |

"Dwell time" is reported only as video watch time (YouTube, Instagram reels). No platform in the set reports reading time for text or image posts, and the panel says so instead of estimating it. The host's own tracked-link clicks are shown for every platform alongside these.

Platforms define these numbers differently (Instagram "views" counts plays; X "impressions" counts times shown). The panel never adds views or impressions across platforms into one total; it shows them per platform with the provider's own metric name.

## Comparison and guidance

The Revenue by source view ranks platforms and accounts by **estimated profit per published post** over the selected period, with posts, human clicks, clicks per post, orders, net revenue, costs and profit alongside.

A source is marked **"Not enough data"** when it has fewer than 5 published posts or fewer than 5 attributed orders in the period (both thresholds configurable). It still appears in the table but is excluded from the "Where to focus" summary, which names the top sources with their sample sizes and the reminder that figures are estimates.

## Configuration

| Setting | Default |
|---|---|
| ATTRIBUTION_WINDOW_DAYS (per workspace) | 7 |
| ATTRIBUTION_HALF_LIFE_HOURS (per workspace) | 48 |
| REPORTING_CURRENCY (per workspace) | USD |
| FX_RATE_SOURCE | ECB daily reference rates |
| STORE_POLL_MINUTES | 15 |
| CLICK_RAW_RETENTION_DAYS | 90 |
| BOT_BURST_THRESHOLD | 20 |
| METRICS_SCHEDULE / METRICS_SCHEDULE_X | As above |
| INSIGHTS_MIN_POSTS / INSIGHTS_MIN_ORDERS | 5 / 5 |

## Acceptance criteria

- Each platform's copy of a post gets its own tracked link; clicks are credited to that target.
- Preview fetches from X, Bluesky, Discord, Telegram and many Mastodon servers after publishing are classified as bots and excluded.
- No IP address, cookie or full referrer URL is stored; visitor digests cannot be linked across days.
- An order with a linked attribution code is credited 100% to its account; other orders split by weighted clicks or fall to Unattributed; shares per line sum to 1.
- Re-importing orders never duplicates them; a refund reported by the store reduces net revenue in the next recompute.
- Missing metrics show as "not reported", never zero; views are never summed across platforms.
- X metric polling stays within the schedule and its cost appears in that account's costs.
- With no public origin, tracked links are disabled and posts publish with the original links.

## References

- [itch.io server-side API](https://itch.io/docs/api/serverside)
- [Jinxxy Creator API access](https://support.jinxxy.com/hc/en-us/articles/28052364650637-How-can-I-access-the-Creator-API) and [Jinxxy changelog](https://feedback.jinxxy.com/changelog)
- [Instagram media insights](https://developers.facebook.com/docs/instagram-platform/reference/instagram-media/insights/)
- [X API metrics](https://docs.x.com/x-api/fundamentals/metrics)
- [TikTok video object](https://developers.tiktok.com/doc/tiktok-api-v2-video-object)
- [YouTube reporting metrics](https://developers.google.com/youtube/reporting/v1/reports/metrics)
- [Mastodon Status entity](https://docs.joinmastodon.org/entities/Status/)
