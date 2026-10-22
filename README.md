# SignalCraft

A self-hosted social publishing workspace. You write a post once and schedule it to several platforms, each at its own time and with its own wording if you want. You then see which platforms actually lead to sales of your itch.io and Jinxxy products.

> **Status:** early development. The design specifications are complete; the core Rails application is being built on the `dev` branch. No addons are implemented yet.

## What it does

- **One draft, many destinations.** A shared post can go to Bluesky at 09:00, Mastodon at 12:30 and Instagram tomorrow at 08:00. Each platform's copy can have different text, media and options without affecting the others.
- **Queues per account.** Recurring time slots per account, drag-to-reorder with keyboard alternatives, pause and resume, and correct handling of daylight-saving changes.
- **Safe publishing.** No post is ever sent twice blindly. If a platform's response is lost, the app checks what happened before doing anything else.
- **Media pipeline.** Uploads are stored in PostgreSQL and converted for each platform by an isolated FFmpeg service. Images you have protected against AI training (for example with Nightshade) are published unchanged.
- **Insights.** Tracked links show clicks from each platform, post and account. Store sales are matched to those clicks to estimate revenue and profit per source. Platform-reported metrics (views, likes, replies, watch time) appear wherever the platform provides them.

## Integrations

| Kind | Integrations |
|---|---|
| Social platforms | Instagram, TikTok, YouTube, X, Bluesky, Mastodon |
| Stores (for sales attribution) | itch.io, Jinxxy |
| Your own bots | Discord through a self-hosted YAGPDB fork, Telegram through your own bot |

## Architecture at a glance

| Component | Technology | Role |
|---|---|---|
| Rails application | Ruby on Rails 8, Hotwire, Solid Queue | Web UI, media endpoints and background worker roles from one image |
| FFmpeg service | Go API on Alpine, sandboxed FFmpeg | Validates and converts media on a private network |
| Database | Your existing PostgreSQL (13 or later) | All application data and media; no Redis, no object storage |
| Addons | Ruby gems | One per platform or store, behind a common addon API |
| Relay bots | YAGPDB fork (Go), your Telegram bot | Post to Discord and Telegram through a shared HTTP protocol |

## Design specifications

All sheets are in [`design specifications/`](design%20specifications/).

### Core

| Sheet | Covers |
|---|---|
| [01 FFmpeg container](design%20specifications/01_FFmpeg_Container_Design.md) | Media service deployment, sandboxing, resource limits |
| [02 Rails container](design%20specifications/02_Rails_Container_Design.md) | Application roles, topology, media storage, scheduling, publishing, credential storage, configuration |
| [03 FFmpeg API](design%20specifications/03_FFmpeg_API_Specification.md) | REST contract for media jobs |
| [04 Addon API](design%20specifications/04_Rails_Plugin_API_Specification.md) | Contract for social and commerce addons, metrics and errors |
| [05 UI design language](design%20specifications/05_Rails_UI_Design_Language.md) | Layout, tokens, composer, queues, Insights, accessibility |
| [06 UI visual reference](design%20specifications/06_UI_Visual_Reference.html) | Static visual companion to sheet 05 |
| [07 Media protection](design%20specifications/07_Media_Protection_Specification.md) | Publishing images you protected against AI training |
| [08 Database schema](design%20specifications/08_Database_Schema_Specification.md) | Tables, constraints, retention, roles, migrations |
| [08 Schema SQL](design%20specifications/08_schema.sql) / [tests](design%20specifications/08_schema_tests.sql) | Reference DDL and constraint tests |
| [09 Insights and attribution](design%20specifications/09_Insights_and_Attribution_Specification.md) | Tracked links, click filtering, sales attribution, profit, post metrics |
| [10 Relay bot protocol](design%20specifications/10_Relay_Bot_Protocol_Specification.md) | HTTP contract between Rails and the Discord and Telegram bots |

### Addons

| Sheet | Addon |
|---|---|
| [2 - 1](design%20specifications/02-1_Instagram_Ruby_Addon.md) | Instagram |
| [2 - 2](design%20specifications/02-2_TikTok_Ruby_Addon.md) | TikTok |
| [2 - 3](design%20specifications/02-3_YouTube_Ruby_Addon.md) | YouTube |
| [2 - 4](design%20specifications/02-4_X_Ruby_Addon.md) | X |
| [2 - 5](design%20specifications/02-5_Bluesky_Ruby_Addon.md) | Bluesky |
| [2 - 6](design%20specifications/02-6_Mastodon_Ruby_Addon.md) | Mastodon |
| [2 - 7](design%20specifications/02-7_itch_io_Ruby_Addon.md) | itch.io (store) |
| [2 - 8](design%20specifications/02-8_Jinxxy_Ruby_Addon.md) | Jinxxy (store) |
| [2 - 9](design%20specifications/02-9_Discord_YAGPDB_Ruby_Addon.md) | Discord through a self-hosted YAGPDB fork |
| [2 - 10](design%20specifications/02-10_Telegram_Bot_Ruby_Addon.md) | Telegram through your own bot |

### Suggested reading order

1. Sheet 02 for the overall application.
2. Sheet 04, then the addon sheets for the platforms you care about.
3. Sheets 08 and 09 for data and Insights.
4. Sheets 01, 03 and 10 for the services around the Rails app.

## Application code

The `dev` branch holds the core Rails application as it is being built; see [DEVELOPMENT.md](DEVELOPMENT.md) for what exists, the directory layout (`/var/www/signalcraft`, with `plugins/` and `config/`), configuration and tests.

## Checking the schema

The reference schema and its constraint tests run on any PostgreSQL 13 or later database you can create and drop:

```bash
createdb signalcraft_schema_check
psql -v ON_ERROR_STOP=1 -d signalcraft_schema_check -f "design specifications/08_schema.sql"
psql -v ON_ERROR_STOP=1 -d signalcraft_schema_check -f "design specifications/08_schema_tests.sql"
dropdb signalcraft_schema_check
```

The test file runs inside a transaction that is rolled back. It prints one `PASS` line per check and ends with `ALL TESTS PASSED`.

## Before implementation

The sheets record each platform's public documentation as of October 2026. Provider rules, prices and limits change, so every addon sheet ends with a "Verify at implementation" list. The largest open items:

- **Jinxxy:** API endpoint details, order fields and webhooks. Its API reference could not be loaded while the sheets were written.
- **X:** current API pricing.
- **Sandbox:** the FFmpeg sandbox (Landlock and seccomp) must be proven on the target host's kernel.
- **Public address:** tracked links, Instagram publishing and Bluesky OAuth all require the server to be reachable from the internet.

---

*Disclaimer: This README and the design specifications in this repository were written by Claude, an AI model made by Anthropic, at the direction of the repository owner. They are proposals that have not been implemented or independently reviewed. Facts about third-party services were checked against public sources in October 2026 and may be out of date. Verify them before relying on them, and treat nothing here as legal, financial or security advice.*
