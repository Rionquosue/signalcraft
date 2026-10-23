# Developing SignalCraft

This is the core Rails application described in `design specifications/02_Rails_Container_Design.md`. Addons (sheets 02-1 to 02-10) are not implemented yet.

## What exists so far

| Area | Status |
|---|---|
| Rails 8.1 application skeleton (Hotwire, Propshaft, import maps, Solid Queue in the app database) | Done |
| Operator configuration: `config/signalcraft.yml`, environment variables and secret files, validated at boot | Done, tested |
| Addon discovery: manifest validation, plugins directory scanning, build lock, database sync | Done, tested |
| Database: full schema from sheet 08 as the first migration, plus Solid Queue tables | Done |
| Core models: users, sessions, login throttling, workspaces, memberships, invitations, addons, social accounts, queues, posts, targets, media assets, publishing intents and attempts, audit and outbox | Done |
| Composer: shared draft, one target per account, schedule table (Queue / Fixed time / Now), "schedule ready only", publish-now confirmation (sheet 05) | Done, tested |
| Per-platform editing: account tabs, "Edited for {platform}", Reset to shared, Copy to new draft for in-flight targets | Done, tested (text only; media and addon options wait for uploads and addon settings) |
| Queue slots with DST rules (`Scheduling::SlotCalendar`, `Scheduling::WallClock`), slot editor with ten-occurrence preview | Done, tested |
| Slot assignment, reorder with preview and version check, Move up/down, pause and resume with preview (`Scheduling::QueueAllocator`, `ChannelQueue`) | Done, tested |
| Grace window and missed schedules (`Scheduling::Lateness`) | Done, tested |
| Dispatcher: outbox drain, claims with leases and fencing tokens, publish intents and snapshots, result mapping, retries, throttles, stale-lease recovery, reconciliation (`app/services/publishing`, `DispatchJob` every `DISPATCH_INTERVAL_SECONDS`) | Done, tested against a fake addon |
| Sign-in and sign-out with digest-only session tokens, login throttling and auditing | Done |
| Queue page: account columns, queue cards with sheet 05 status language | Done, tested |
| Health endpoints `/health/live` and `/health/ready` | Done |
| Docker image, entrypoint and example compose file | Built and smoke-tested (read-only root, UID 10001, health checks) |
| Media uploads, FFmpeg client, credential refresh, host HTTP client, Insights, addons, History and Calendar pages | Not started |

### Known limits of the publishing path

- Targets with media are blocked as `media_unavailable` until media preparation (`prepare_media`, variants, signed fetches) exists.
- `AuthenticationExpired` blocks the target as `reauthorization_required`; the credential refresh lease comes with account connections.
- An addon only publishes when its workspace has enabled it (`workspace_plugins.enabled`); there is no Settings → Plugins page yet, so enable it from the console.
- Tracked links are not substituted into snapshots yet (sheet 09).
- The composer has no autosave; "Save draft" saves text and schedule choices.

## Directory layout

In a deployment the application lives at `/var/www/signalcraft`:

| Path | Contents |
|---|---|
| `/var/www/signalcraft` | The application (this repository's root) |
| `/var/www/signalcraft/plugins` | Addon gems, one directory each, baked into the image at build time. See `plugins/README.md`. |
| `/var/www/signalcraft/config/signalcraft.yml` | Operator configuration, mounted read-only. Template: `config/signalcraft.example.yml`. |
| `/var/www/signalcraft/config/secrets/` | Secret files, mounted read-only. |

The rest of `config/` is the application's own Rails configuration, so only `signalcraft.yml` and `secrets/` are mounted, not the whole directory.

## Configuration

Settings come from built-in defaults, then `config/signalcraft.yml`, then upper-case environment variables. Secrets are only ever read from files, named by `<key>_file` in the YAML file or `<KEY>_FILE` in the environment. An inline secret is an error. All problems are reported together and stop the boot.

```bash
bin/rails signalcraft:check_config   # validate and print settings with secrets redacted
```

The full list of settings, with types and limits, is in `lib/signal_craft/settings.rb`.

## Local setup

Requirements: Ruby 3.3 or later, PostgreSQL 13 or later with a role that can create databases.

```bash
bundle install
bin/dev-config --database-host localhost --database-user "$USER"   # throwaway config and secrets
bin/rails db:create db:migrate
bin/rails server
```

`bin/dev-config` refuses to run in production and never overwrites existing files.

Create a first user and workspace from the console:

```ruby
user = User.create!(email: "you@example.com", display_name: "You", password: "a long passphrase here")
workspace = Workspace.create!(name: "Studio")
Membership.create!(workspace: workspace, user: user, role: "owner")
```

## Tests

| Command | What it covers | Needs |
|---|---|---|
| `bin/rails test:lib` (or `ruby -Ilib -Itest test/lib/settings_test.rb`) | Settings, addon manifests, plugins directory and lock | Ruby only |
| `bin/check-schema-sync` | The migration SQL matches `design specifications/08_schema.sql` | Ruby only |
| `bin/rails test` | Models, controllers, addon sync, enum and database agreement | Gems and PostgreSQL |
| `psql -f "design specifications/08_schema_tests.sql"` | Database constraints | PostgreSQL |

CI (`.github/workflows/ci.yml`) runs all four on every push to `main` and `dev`; all pass on `dev`. Test failures are also reported as check-run annotations (`bin/ci-annotate-failures`), grouped by cause.

## Lockfile and structure dump

- **`Gemfile.lock`** is committed for `x86_64-linux` and `aarch64-linux` (Rails 8.1.4). Add platforms with `bundle lock --add-platform`.
- **`db/structure.sql`** is committed and regenerated by `bin/rails db:migrate`. A rake hook strips `SET transaction_timeout`, which pg_dump 17 writes but PostgreSQL 16 and older reject.

## Database notes

- The first migration executes `db/sql/0001_core_schema.sql`, a copy of the specification's reference DDL. `bin/check-schema-sync` fails if they differ. Schema changes are made in both places, as a new migration plus an update to the specification. Because `0001` always holds the current schema, a fresh database already has each change; write later migrations so they are no-ops in that case (see `20261023000001_relax_queue_entry_slot_check.rb`).
- Lock order: a queue's `channel_queues` row is locked before any of its targets, by allocation, scheduling, claims and sends alike, so they never deadlock.
- Solid Queue's tables are created by the second migration, following Solid Queue's single-database setup (copied from solid_queue v1.7.0).
- Enum values in models must match the database's check constraints; `test/models/enum_consistency_test.rb` enforces this.
- Primary keys are UUIDv7 values generated in `ApplicationRecord`.

## Passwords

Rails 8.1's `has_secure_password` supports only bcrypt, so passwords use bcrypt at the configured cost (default 12), as sheet 02 specifies for this case. Hashes are upgraded at login when the cost increases. Argon2id follows when Rails ships the `algorithm:` option.
