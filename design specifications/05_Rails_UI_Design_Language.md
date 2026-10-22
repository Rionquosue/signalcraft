# Rails application — UI design language sheet

Design system 1.2 • 22 October 2026 • Proposed product interface

## Direction

A quiet, compact publishing workspace: the parallel visibility of TweetDeck/X Pro columns, the clear composition and queue workflow associated with Buffer, and the calendar/list views common to social management products. Use original layouts and assets rather than reproducing branding.

The queue is the default landing page. The core unit shown in a channel column is a **publication target**, not a shared post. A shared post may appear in several columns with different content, dates and outcomes.

See **06_UI_Visual_Reference.html** for the visual companion: desktop queue, independent scheduling composer, component tokens and responsive guidance. It is a static design reference, not a working application.

## Navigation and information architecture

| Area | Contents |
|---|---|
| Queue | Default account columns; list toggle, account filters and queue controls |
| Calendar | Week/month schedule across accounts; account-specific chips |
| Drafts | Shared posts, last edited time, target readiness |
| Media | Uploaded originals and processed variants, usage and validation status |
| History | Published, failed, cancelled and uncertain targets; attempt details |
| Insights | Revenue by source (store sales attributed to platforms, accounts and posts) and Post performance (platform-reported metrics) |
| Accounts | Social accounts (connections, reconnect actions, queue slots, account timezone, profile links) and Stores (itch.io and Jinxxy connections, fee settings, attribution codes) |
| Settings | Workspace members, plugins, display preferences and administration |

Desktop left rail: 208 px expanded, 64 px collapsed. Top bar: 64 px with workspace, search and New post. Main toolbar: view toggle, account filter, date filter and display timezone. No dedicated live social inbox in v1; columns show this application's publishing work.

## Visual tokens

| Token | Light theme | Dark theme | Usage |
|---|---|---|---|
| Canvas | #F4F6FA | #111827 | Workspace background |
| Surface | #FFFFFF | #1F2937 | Cards, drawers, menus |
| Text primary | #172033 | #F3F4F6 | Body and headings |
| Text secondary | #526078 | #BCC6D6 | Metadata |
| Border decorative | #DCE2EA | #3D4B60 | Card separators |
| Border control | #748096 | #8795AB | Inputs and controls requiring boundary contrast |
| Accent | #2457D6 | #A8C5FF | Primary action; dark buttons use dark text |
| Selected surface | #EAF0FF | #223656 | Active account, selected card |
| Success text | #166534 | #86EFAC | Published |
| Warning text | #854D0E | #FDE68A | Paused, attention |
| Error text | #B91C1C | #FCA5A5 | Failed, validation |

Use system sans-serif fonts; no mandatory external font loading. Body 14 px/20 px, secondary metadata 12 px/16 px, section title 20 px/28 px, page title 26 px/32 px. Form controls and essential scheduling data remain at least 14 px. Use tabular numerals for times and counters.

Spacing scale: 4, 8, 12, 16, 24, 32 px. Cards: 10 px radius, 1 px border, 16 px internal padding. Controls: 8 px radius, at least 36 px desktop height and 44 px touch targets. Modal/drawer: 12 px radius. Shadows only for elevated menus and overlays; no decorative gradients.

Icon style: simple 18–20 px outline icons with visible labels for key actions. Service identity is expressed with account name, handle and restrained icon; color alone never identifies a service. Use approved platform assets only when licensing permits.

## Queue view

At wide desktop sizes, show 3–4 independently scrolling channel columns, each 304–360 px wide. Horizontal overflow stays within the board; the page header and sidebar stay fixed. A list view is always available.

Column header contains service + account, timezone, future count, next slot and Pause/Resume. A filter or pause indicator never disappears when scrolling. Pause is shown as an account indicator in the column header ("Account paused"), not as a badge on each card: target state and account pause are separate.

### Queue card anatomy

1. Slot time and date in the chosen display timezone.
2. Text preview, up to four lines, with an explicit Expand control.
3. Optional thumbnail and descriptive media count.
4. State label, schedule mode (Queue / Fixed time), and override indicator.
5. Edit, overflow menu and keyboard-accessible Move action.

Empty slots show a subdued Add to this slot action. Queued cards have a drag handle and Move up/down/menu alternatives. Fixed-time cards show a pin and cannot be reordered as queue entries. Published cards leave the queue for History.

Drag across accounts is not a silent move. It opens a destination-copy dialog, validates platform constraints, and asks whether to add a new target; never remove the original automatically.

Queue reordering previews changed dates and commits atomically. An optimistic-lock conflict refreshes the list with “This queue changed. Review the updated order.” Preserve the intended move so the user can retry.

## Composer and independent publishing times

Desktop composer: 960–1120 px modal or full-page route with three sections: shared content, per-account customization, scheduling summary. Narrow screens use a full-page form with those sections stacked.

Select accounts first, then enter shared text and media. Each account tab shows validation, provider-specific counters, alt-text support and overrides. A changed shared draft updates inherited fields only; overridden fields stay unchanged and show Reset to shared.

The schedule table has one row per connected account:

| Service/account | Mode | Date/time | Zone | Status |
|---|---|---|---|---|
| Bluesky / Studio | Queue | Next slot: 23 Oct, 09:00 | America/Toronto | Ready |
| Mastodon / Studio | Fixed time | 23 Oct, 12:30 | America/Toronto | Ready |
| Instagram / Studio | Fixed time | 24 Oct, 08:00 | America/Toronto | Ready |

Allow “Use this time for all” as an explicit convenience that changes selected rows to fixed-time mode. It is never the default and must not erase account content overrides.

Footer primary action: **Schedule 3 publications**. Secondary: Save draft. Now mode uses the explicit action **Publish 1 now**, with a summary of any later targets. Mixed immediate/future targets get a confirmation listing which accounts publish now. If a Now target's account is paused, the confirmation says it will not publish until the account is resumed, and offers Resume account or Keep as scheduled.

If one target is invalid, disable the combined action and focus its error. Offer “Schedule ready targets only” as an explicit secondary choice with an exact count; remaining targets stay draft. Never silently omit an account.

Autosave shared drafts and overrides with a visible Saving / Saved / Save failed indicator. On failure retain local form state for the current session, offer retry, and warn before navigating away. Scheduling requires a confirmed save.

### Editing a queued post for one platform

Every platform's copy of a post can be changed on its own, before or after scheduling, without affecting the other platforms. For example, the X copy can get shorter text and a different image while Bluesky and Mastodon keep the shared version.

- **Entry points:** "Edit for {platform}" on any queued or scheduled card's menu, and the account tabs in the composer. Both open the composer with that account's tab selected.
- **What can differ per platform:** text, media (selection, order and alt text), and platform options such as visibility, title or content warning. The tab shows that platform's own counter, limits, link cost and media rules.
- **Inheritance:** a field the user has changed for one platform is marked "Edited for {platform}" and keeps its value when the shared draft changes. Fields not changed keep following the shared draft. "Reset to shared" per field restores inheritance.
- **Scheduling is untouched:** editing content never moves a queued post out of its slot or changes a fixed time. Changing the time is a separate action.
- **Revisions:** saving creates a new revision of that platform's target only (02). Other targets keep their revisions.
- **When editing is not allowed:** once a target is Preparing media or Publishing, the menu offers "Copy to new draft" instead, and the in-flight publication is not changed. Published targets cannot be edited in v1.
- **Tracked links:** a link added or changed in one platform's text gets its own tracked link for that platform (09).
- **Preview:** the side preview follows the selected tab, so the user sees exactly what each platform will receive.

### Media upload

Uploads run in chunks and show real transferred bytes, so an upload percentage is allowed (unlike processing). An interrupted upload shows "Upload paused · Resume" and continues from the last stored chunk, including after a page reload in the same session. After upload, the asset shows a placeholder labeled "Checking media" until the processor validates it; no preview of the raw file is shown before then. Media options that need a public media URL show "Not available on this server" with an explanation when the deployment has no public media origin.

### AI-training protection

Each image has a checkbox, "I protected this image against AI training", with help text: "We'll publish this exact file without resizing or converting it. Protection tools aren't a guarantee, and platforms may still recompress images." Declared images show a "Protected (declared)" badge with the tool name if given. The checkbox is not shown for video. A provider whose limits the file breaks shows the blocked message from 07_Media_Protection_Specification.md with two choices: upload a compliant protected version, or untick protection.

### Provider-specific composer behavior

The v1 providers are Instagram, TikTok, YouTube, X, Bluesky and Mastodon. All of this comes from plugin capabilities; the composer never hard-codes it.

| Situation | Composer behavior |
|---|---|
| Text-only post with Instagram, TikTok or YouTube selected | Account tab shows "Needs a photo or video" and the row cannot be scheduled until media is added; other accounts are unaffected |
| Instagram on a server without a public media origin | Account shown as "Not available on this server" in account selection, with a link to the explanation |
| TikTok client not yet audited by TikTok | Visibility control fixed to private, with the note "TikTok only allows private posts from this app until it is approved" |
| TikTok privacy and interaction options | Options come from the creator's current settings, fetched when the tab opens; unavailable choices are disabled with a reason |
| YouTube daily upload allowance | Row shows remaining uploads for the day when low; at zero, the row offers the next day instead of failing at publish time |
| X paid API | Row shows "Uses paid API credits" and the higher cost for posts with links; if the monthly budget would be exceeded, the row is blocked with an owner-facing explanation |
| Image too large or wrong format for a provider | "An adjusted copy will be made for {account}" note; the variant is generated automatically and previewed before scheduling |
| Mastodon instance limits | Character counter and media limits use the selected instance's own values |
| Links on Instagram and TikTok | Caption links are not clickable; the tab shows "Links aren't clickable on {platform}. Your profile link: [copy]" with that account's tracked profile link |
| Store links | "Insert store link" opens a picker of connected itch.io and Jinxxy products; the link is tracked per platform with a "Track clicks" toggle (on by default) |
| Jinxxy attribution code | If an account has a linked code, its tab offers "Add your {code} offer" to insert it |
| Discord (YAGPDB) | Text over 2,000 characters is sent as two messages; the tab says so. Mentions are limited to roles allowed for that channel |
| Telegram | Text over 1,024 characters with media is sent as media followed by a separate text message; the tab says so |
| Tracked links unavailable | On servers without a public address, "Track clicks" is disabled with "Click tracking needs a public address for this server" |

## Scheduling and timezone interaction

Display the active timezone in every calendar, queue toolbar and composer schedule section. A local time tooltip includes the UTC offset and account timezone when different. Dates use unambiguous day + month labels; include year at year boundaries.

Queue slot editor: weekday chips, times and IANA timezone, with a preview of the next ten occurrences. Explain the project's DST rules next to the preview: nonexistent slots are skipped; repeated slots run once at the first occurrence.

Pause dialog: “Pause all new publications for this account? Publications already sending may finish.” Resume dialog previews future reallocation and lists overdue fixed-time items needing a decision.

Lateness follows the host's grace window (default 15 minutes). A target that is late but within the window shows "Publishing shortly" rather than an error. Beyond the window, queue items move to their next slot (shown in the Resume preview or as a notice after an outage), and fixed-time items show "Schedule missed" with Publish now and Reschedule actions.

Calendar drag opens a confirmation that switches the selected target to Fixed time and shows old/new time. A shared post's other targets remain unchanged. List agenda is the accessible and narrow-screen calendar fallback.

## Insights

Two tabs share a date range picker (default: last 30 days), an account and platform filter, and the reporting currency.

### Revenue by source

- **Summary card, "Where to focus":** the top platforms or accounts by estimated profit per post, each with its posts and orders count, and the note "Estimated from link clicks; see how this is calculated". Sources marked "Not enough data" are left out of the card.
- **Table** grouped by platform, expandable to accounts and then posts:

| Column | Content |
|---|---|
| Source | Platform, account or post (with its scheduled time) |
| Posts | Published posts in the period |
| Clicks | Human clicks on tracked links (bot-filtered) and clicks per post |
| Orders (est.) | Attributed order lines, as a decimal sum of shares, with the exact (code) part shown separately |
| Net revenue (est.) | After refunds and store fees, in the reporting currency |
| Costs | Paid API costs plus manual costs for that source |
| Profit (est.) | Net revenue minus costs |
| Profit per post | Profit divided by posts |

- An **Unattributed** row is always shown, so the user sees how much revenue had no linked click.
- Estimated values are labelled "est."; fees that were estimated rather than reported get a dotted underline with a tooltip.
- **"How this is calculated"** opens a drawer explaining the model in plain language: exact codes, click share over the attribution window, the recency weighting, and the known limitations from 09.
- Owners can change the attribution window and half-life in the drawer; changing them shows "Recalculating…" until the recompute finishes.
- Manual costs are added from the table ("Add cost" per row) or Accounts → Stores.

### Post performance

- One row per published post per platform, with columns for each metric. A metric the platform does not report shows "—" with the tooltip "{Platform} doesn't report {metric}", never 0.
- Metric names follow the platform's own wording in tooltips (for example "Instagram: views (plays)", "X: impressions").
- Watch time appears only for video posts on YouTube and Instagram reels; elsewhere the column explains "Not reported for this kind of post".
- Each row also shows tracked-link clicks and estimated revenue for that post, so engagement and sales sit side by side.
- A small trend line per metric shows the snapshots over time; "Last updated {time}" reflects the polling schedule.
- Views and impressions are never totalled across platforms.

### Empty and limited states

| Situation | Copy |
|---|---|
| No store connected | "Connect itch.io or Jinxxy to see which posts lead to sales." Connect store action |
| Store connected, no tracked links yet | "Add store links to your posts to start measuring clicks." |
| Not enough data | Row badge "Not enough data" with "Fewer than 5 posts or orders in this period" |
| Store import failing | Banner on the store row with the last error and Reconnect |
| X metrics budget reached | "X metrics paused: monthly budget reached" on X rows |

## Status language

| State | Visible label | Action |
|---|---|---|
| draft | Draft | Continue editing |
| scheduled, queue mode | Queued | Edit / Move / Set fixed time |
| scheduled, manual mode | Scheduled | Edit / Reschedule |
| preparing | Preparing media | View progress / Cancel |
| publishing | Publishing | View status |
| awaiting_provider | Processing on service | View status |
| published | Published | View on service |
| retry_wait | Retry scheduled · time | View reason |
| blocked | Needs connection or Plugin unavailable | Reconnect / Manage plugin |
| needs_attention, publication_unconfirmed | Publication unconfirmed | Check status / Open account / Resolve |
| needs_attention, schedule_missed | Schedule missed | Publish now / Reschedule |
| needs_attention, unsupported_checkpoint_version | Needs owner review (after a rollback) | Contact owner / View details |

The label for `needs_attention` always comes from the stored `attention_reason`; never infer it from timing or history.
| failed | Failed | Edit / Retry when safe |
| cancelled | Cancelled | Duplicate as draft |

Use labeled badges with distinct symbols. Failed and unconfirmed are different: unconfirmed must not have a prominent blind Retry button. Offer Check status, Open account and a deliberate “I verified it was not published” recovery flow. Show a duplicate-risk confirmation before a manual new attempt.

Post-level summary can read “1 published · 1 scheduled · 1 needs attention.” Never show overall Published while outstanding targets remain.

## Plugin-driven UI

Accounts presents installed providers with Connect and a capability summary. A plugin can provide declarative settings and validation; the host renders consistent controls. Unsupported media options are disabled with an explanation, not hidden until publishing.

Settings → Plugins is owner-only. Show version, compatibility, enabled state, affected accounts and pending publications. Disable/uninstall dialogs show impact. No upload-code button in v1.

Viewer permissions remove publishing/edit actions; editor can compose and schedule; owner manages membership and plugins. Server authorization remains authoritative.

## Responsive and accessibility rules

| Width | Layout |
|---|---|
| ≥1280 px | Expanded rail, column board, wide composer |
| 900–1279 px | Collapsed rail, 2–3 visible columns, horizontal board navigation |
| <900 px | One selected-account queue or chronological list, full-page composer |
| <600 px | Compact top navigation, labeled bottom navigation or menu, stacked schedule rows |

Target WCAG 2.2 AA. Verify text contrast at 4.5:1, large text at 3:1 and essential UI boundaries/focus at 3:1. Decorative borders need not carry control meaning. Visible two-pixel focus outlines; keyboard operability for all menus, dialogs, queues and dates. Restore focus after closing overlays.

No drag-only workflow, color-only state, hover-only action, or icon-only essential command. Associate errors with fields and announce state changes politely. Respect reduced motion; keep transitions 120–160 ms and avoid column-shifting animations. Do not move focused cards unexpectedly after a background refresh.

New post shortcut N works only outside text inputs. Escape closes a menu/dialog after resolving unsaved changes, never publishes. Document shortcuts in a help panel.

## Empty, loading and error states

| Situation | Copy and behavior |
|---|---|
| No accounts | “Connect an account to start scheduling.” Connect account action |
| No queue slots | “Choose posting times for this account.” Edit schedule action |
| Empty queue | “Your queue is clear.” Create post action |
| Media validation | "Checking media" placeholder; raw upload never previewed |
| Media processing | Thumbnail placeholder plus Preparing media, no fake percentage |
| Upload interrupted | "Upload paused · Resume"; continues from the last stored chunk |
| Offline / failed save | Persistent banner and retry action; preserve typed content |
| Provider outage | Account-level issue banner; other account queues remain usable |
| Stale queue edit | Refresh and review changes; do not silently overwrite |
| Partial success | Per-target results; retry only eligible failed targets |

## UI acceptance scenarios

1. Create a shared post and schedule three accounts at three times without duplicating the draft.
2. Override one account's text; shared edits preserve the override.
3. Move a queued target by keyboard; show changed dates before saving.
4. Pause one account; sibling targets on other services continue.
5. Resolve an uncertain provider response without a blind retry.
6. Complete composer and schedule controls at 200% zoom and keyboard-only.
7. Show disconnected/unsupported plugin states without losing drafts.
8. Use one-account queue and stacked scheduling rows on a phone.
9. Interrupt a large upload and resume it without re-sending stored chunks.
10. Show a missed fixed-time target with its reason and actions after an outage longer than the grace window.
11. Select Instagram, TikTok and YouTube for a text-only post; each row explains the media requirement while X, Bluesky and Mastodon remain schedulable.
12. Change only the X copy of a queued post (text and image); the other platforms keep the shared content and every post keeps its slot.
13. See an order attributed by code to Bluesky and an order split by clicks between X and Mastodon, with the Unattributed row and the method drawer.
14. Open Post performance and see "—" with an explanation for metrics a platform does not report.

## Reference basis

- [X Pro columns](https://help.x.com/en/using-x/how-to-use-x-pro) — side-by-side column inspiration.
- [Buffer scheduling](https://support.buffer.com/en-us/articles/scheduling-posts-4Qdld7giAZ) — queue/composer workflow reference.
- [Buffer queue pause](https://support.buffer.com/en-us/articles/pausing-your-queue-12mcPkutFk) — pause interaction reference.

Colors, dimensions, state labels, layout and scheduling semantics here are original project decisions. Actual provider capabilities are supplied by installed plugins.

## Changes in 1.2

- Added the Insights area (Revenue by source, Post performance) and Stores under Accounts.
- Made per-platform editing of queued posts explicit.
- Added composer behavior for tracked store links, profile links, attribution codes, Discord and Telegram.

## Changes in 1.1

- Added the `awaiting_provider` state ("Processing on service") and split `needs_attention` labels by stored `attention_reason`.
- Pause is an account indicator in the column header, not a card badge.
- Added media upload behavior: chunked progress, resume, "Checking media" placeholder before validation, and unavailable fetch-by-URL options.
- Described the missed-schedule grace window and paused-account handling for Publish now.
- Added acceptance scenarios for upload resume and missed schedules.
- Added the AI-training protection checkbox (07_Media_Protection_Specification.md).
- Replaced LinkedIn with Instagram in examples; added provider-specific composer behavior for the v1 provider set.
- 06_UI_Visual_Reference.html updated to match this sheet's dimensions, type sizes and breakpoints.
