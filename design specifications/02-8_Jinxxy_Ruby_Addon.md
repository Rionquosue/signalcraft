# 2 - 8 Jinxxy Ruby addon — specification sheet

Addon 1.0 • 22 October 2026 • plugin_id `jinxxy` • kind `commerce`

Provider facts are from Jinxxy's support article, changelog and third-party integrations as of October 2026. Jinxxy's own API reference (`https://api.creators.jinxxy.com/docs`) could not be loaded while this sheet was written, so every endpoint detail below must be confirmed against it before implementation. The commerce contract is in 04; attribution is in 09.

## Purpose

Import your Jinxxy products and orders so Insights can estimate, and where possible measure exactly, which social platforms drive sales.

## What is known about the Creator API

| Topic | What is known | Source |
|---|---|---|
| Base URL | `https://api.creators.jinxxy.com/v1/` | Third-party loader example |
| Authentication | API key from the creator dashboard, sent as `x-api-key` | Third-party loader example; support article |
| Data | Products, customers, discount codes, licenses and order information; licenses include order information and orders include license information (January 2026) | Support article; changelog |
| Webhooks | "Realtime webhooks" are offered; one integration validates them with an HMAC signature | Support article; YUCP Creator Assistant |
| Scopes | API keys carry scopes such as `products_read`, `discount_codes_write`, `licenses_read`, `licenses_write`; an orders-read scope is expected | Jinx bot documentation |
| Discount codes | Can be created, edited and deleted through the API (January 2026) | Changelog |
| Affiliate codes | Sellers can give promoters affiliate URLs or codes that credit them a percentage of each sale and see revenue per code (April 2026); API access to this is not confirmed | Changelog |
| Fees | Jinxxy's platform fee was not found in public sources | — |

## Manifest

```yaml
id: jinxxy
kind: commerce
name: Jinxxy
plugin_api: ">=1.2 <2.0"
auth:
  strategy: api_key
  scopes: [products_read, orders_read, discount_codes_write]   # confirm names
capabilities:
  webhooks: true             # confirm event types and signature scheme
  refunds_visible: true      # confirm
  fees_reported: false       # set true if order data includes fees
  attribution_codes: discount   # affiliate if the API exposes affiliate codes on orders
  order_history_days: null
settings:
  - key: platform_fee_percent
    type: decimal
    help: "Jinxxy's fee, from your payout statements"
  - key: payment_fee_percent
    type: decimal
    default: 0
```

## Import behavior

| Task | Behavior |
|---|---|
| Products | `list_products` reads products every 6 hours: ID, name, store URL, price and currency. |
| Orders | Webhook order events are the primary path; `fetch_orders` also runs every 15 minutes from a saved cursor to catch missed events. Orders are deduplicated by order ID, and refunds update the existing order. |
| Personal data | Customer and license holder details are discarded inside the addon. Only order ID, products, amounts, status, codes used and time are returned. |
| Webhooks | Registered against a store-account webhook endpoint (`/integrations/jinxxy/webhooks/{token}`, 04). `verify_webhook` checks the signature with the stored secret over the raw body and rejects events older than 5 minutes. |

## Exact attribution with codes

Jinxxy is the one store in the set where some sales can be attributed exactly, if order data includes the code used. The owner can opt in per social account:

1. In Accounts → Stores → Jinxxy → Attribution codes, the owner creates a code for an account (for example `BSKY10` for Bluesky), choosing the discount and products. The addon creates it with `create_attribution_code` (discount codes, through the API), and the host links it to that social account.
2. The composer can insert the account's code into that platform's version of a post ("Use code BSKY10 for 10% off").
3. An order that used a linked code is credited 100% to that account (09, method `code`). Orders without a code fall back to click share.

Discount codes reduce revenue per sale, and Insights computes net revenue after the discount. If Jinxxy's affiliate codes turn out to be readable on orders through the API, they can be used the same way, but they pay the promoter a commission, so they only make sense when the promoter is a real third party.

## Errors

| Condition | Handling |
|---|---|
| 401 or 403 | ReauthorizationRequired: "Reconnect" on the store connection |
| Webhook signature invalid | Rejected; counted in the endpoint's failure log |
| 429 or 5xx | Back off and retry the import later; the cursor is kept |

## Addon-specific tests

Webhook signature verification and replay rejection, order deduplication between webhooks and polling, refund updates, customer data removal, discount code creation and order-to-code matching.

## Verify at implementation

All endpoint paths, order fields (amounts, currency, fees, discount and affiliate codes, refunds), webhook event names and signature header, scope names, rate limits and Jinxxy's fee structure, from the API reference and Jinxxy's Discord #api-chat channel.

## References

- [How can I access the Creator API? (Jinxxy support)](https://support.jinxxy.com/hc/en-us/articles/28052364650637-How-can-I-access-the-Creator-API)
- [Jinxxy changelog](https://feedback.jinxxy.com/changelog)
- [Jinxxy Creators API loader (dltHub)](https://dlthub.com/context/source/jinxxy-creators-api)
- [Jinx Discord bot](https://github.com/zkxs/jinx) and [YUCP Creator Assistant](https://github.com/Yeusepe/YUCP-Creator-Assistant)
