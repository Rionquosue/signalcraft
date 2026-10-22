# 2 - 7 itch.io Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `itch_io` • kind `commerce`

Provider facts are from itch.io's server-side API documentation as of October 2026 and are re-verified at implementation. The commerce contract is in 04; attribution is in 09.

## Purpose

Import your itch.io games and their purchases so Insights can estimate which social platforms and posts drive sales.

## What itch.io's API provides

| Endpoint | Scope | Used for |
|---|---|---|
| `GET /profile/games` | `profile:games` | Products: name, URL, price, and per-game totals: `views_count`, `downloads_count`, `purchases_count`, `earnings` (per currency) |
| `GET /games/{id}/purchases` | `game:view:purchases` | Orders: `id`, `status`, `purchase_type`, `donation`, `currency`, `price` (a formatted string such as "$1.00"), `sale_rate`, `quantity`, `created_at`, and buyer `email` |
| `GET /credentials/info` | — | Validating the key and showing its scopes |

All calls go to `api.itch.io` with `Authorization: Bearer`. What the API does not provide:

- **Referrers.** itch.io shows referrers in its dashboard analytics only. Attribution therefore relies on tracked links (09).
- **Refunds.** Only completed purchases are listed, so refunds are not visible and revenue can be overstated.
- **Fees.** Amounts are not described as gross or net. itch.io's revenue share is chosen by each creator, so fees are estimated from settings the owner enters.
- **Pagination and rate limits** are not documented.

## Manifest

```yaml
id: itch_io
kind: commerce
name: itch.io
plugin_api: ">=1.2 <2.0"
auth:
  strategy: api_key        # OAuth with the scopes below is supported where an OAuth app is registered
  scopes: [profile:games, game:view:purchases]
capabilities:
  webhooks: false
  refunds_visible: false
  fees_reported: false
  attribution_codes: none
  order_history_days: null   # full history, subject to pagination verification
settings:
  - key: revenue_share_percent
    type: decimal
    help: "The share you give itch.io (set on your itch.io account; 10% is the usual default)"
    default: 10
  - key: payment_fee_percent
    type: decimal
    help: "Estimated payment-processor fee"
    default: 3.5
  - key: payment_fee_fixed_minor
    type: integer
    help: "Fixed processor fee per order, in cents"
    default: 30
```

The fee defaults are placeholders the owner should replace with figures from their own itch.io payouts; the UI labels resulting profit as estimated.

## Credentials

Prefer an OAuth-issued key limited to the two scopes above. A personal API key from itch.io settings is unscoped and can do everything the account can, so the connection form warns about this when one is pasted. Either is stored encrypted (02, Credential storage).

## Import behavior

| Task | Behavior |
|---|---|
| Products | `list_products` reads `/profile/games` every 6 hours; each game is a product with its page URL. Games removed from the account are marked inactive. |
| Orders | `fetch_orders` reads `/games/{id}/purchases` for each active game every 15 minutes, keeps the highest `created_at` seen per game in addon state, and returns purchases from 1 hour before that point (to catch late writes); the host deduplicates by purchase ID. |
| Price parsing | `price` is parsed with the purchase's `currency` into minor units (for example "$1.00" USD → 100). Unknown formats raise an error for that purchase and are reported to the owner; they are never treated as zero. `quantity` multiplies the line amount. |
| Donations and rewards | Donation purchases are revenue like any other; claimed-reward data is never fetched (it contains mailing addresses). |
| Personal data | `email` and any other buyer field is discarded inside the addon before returning the order. |
| Store page totals | `views_count`, `downloads_count` and `purchases_count` are snapshotted daily for context in Insights (store page views versus tracked clicks). |

## Attribution notes

- No codes are available, so itch.io orders are attributed by click share (09).
- Tracked links point to game page URLs. itch.io ignores the UTM parameters the redirect adds, which is harmless.
- Check after launch whether itch.io's own referrer report still shows the social sites for visits through tracked links, since the redirect sits between them.

## Errors

| Condition | Handling |
|---|---|
| 401 or 403 | ReauthorizationRequired: the store connection shows "Reconnect" |
| 429 or 5xx | Delay the next import with backoff; never drop the cursor |
| Unparseable price | That purchase is skipped and listed under "Import problems" |

## Addon-specific tests

Price parsing for several currencies and formats, quantity handling, email removal, cursor resumption after interruption, deduplication of re-imported purchases and the unscoped-key warning.

## Verify at implementation

Pagination of the purchases endpoint, whether `price` is the buyer price before or after itch.io's share, what `source` and `sale_rate` mean, rate limits, and current scope names.

## References

- [itch.io server-side API](https://itch.io/docs/api/serverside)
