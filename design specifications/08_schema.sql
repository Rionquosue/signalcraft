-- Social publishing application — PostgreSQL schema
-- Companion to 08_Database_Schema_Specification.md (schema 1.2, 23 October 2026)
-- Requires PostgreSQL 13 or later. No extensions required.
-- Reference DDL: production migrations are written as Rails migrations that
-- produce this structure. Solid Queue creates its own solid_queue_* tables.
-- Encrypted columns hold Active Record Encryption ciphertext (JSON text).

BEGIN;

-- ---------------------------------------------------------------------------
-- Identity and tenancy
-- ---------------------------------------------------------------------------

CREATE TABLE users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email           text NOT NULL CHECK (length(email) BETWEEN 3 AND 320),
  -- Self-describing salted hash string; Argon2id preferred, bcrypt accepted (02, Credential storage).
  password_digest text NOT NULL CHECK (password_digest ~ '^\$(argon2id\$v=19\$|2[aby]\$[0-9]{2}\$)'),
  display_name    text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 100),
  timezone        text NOT NULL DEFAULT 'America/Toronto',
  disabled_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_key ON users (lower(email));

CREATE TABLE sessions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  token_digest bytea NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
  ip_address   inet,
  user_agent   text CHECK (length(user_agent) <= 512),
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL
);
CREATE INDEX sessions_user_id_idx ON sessions (user_id);
CREATE INDEX sessions_expires_at_idx ON sessions (expires_at);

CREATE TABLE login_throttles (
  key_digest        bytea PRIMARY KEY CHECK (octet_length(key_digest) = 32),
  scope             text NOT NULL CHECK (scope IN ('email', 'ip')),
  window_started_at timestamptz NOT NULL,
  attempt_count     integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  locked_until      timestamptz,
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_throttles_updated_at_idx ON login_throttles (updated_at);

CREATE TABLE workspaces (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                 text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  default_timezone     text NOT NULL DEFAULT 'America/Toronto',
  media_quota_bytes    bigint NOT NULL CHECK (media_quota_bytes > 0),
  media_reserved_bytes bigint NOT NULL DEFAULT 0 CHECK (media_reserved_bytes >= 0),
  reporting_currency   char(3) NOT NULL DEFAULT 'USD' CHECK (reporting_currency ~ '^[A-Z]{3}$'),
  attribution_window_days     smallint NOT NULL DEFAULT 7 CHECK (attribution_window_days BETWEEN 1 AND 30),
  attribution_half_life_hours integer NOT NULL DEFAULT 48 CHECK (attribution_half_life_hours BETWEEN 1 AND 720),
  archived_at          timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  role         text NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, user_id)
);
CREATE INDEX memberships_user_id_idx ON memberships (user_id);

CREATE TABLE invitations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces ON DELETE CASCADE,
  email        text NOT NULL CHECK (length(email) BETWEEN 3 AND 320),
  role         text NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
  token_digest bytea NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
  invited_by   uuid REFERENCES users ON DELETE SET NULL,
  expires_at   timestamptz NOT NULL,
  accepted_at  timestamptz,
  accepted_by  uuid REFERENCES users ON DELETE SET NULL,
  revoked_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (accepted_at IS NULL OR revoked_at IS NULL)
);
CREATE UNIQUE INDEX invitations_open_email_key
  ON invitations (workspace_id, lower(email))
  WHERE accepted_at IS NULL AND revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- Plugins and provider connections
-- ---------------------------------------------------------------------------

CREATE TABLE plugins (
  plugin_id    text PRIMARY KEY CHECK (plugin_id ~ '^[a-z][a-z0-9_]{0,63}$'),
  kind         text NOT NULL CHECK (kind IN ('social', 'commerce')),
  version      text NOT NULL,
  plugin_api   text NOT NULL,
  manifest     jsonb NOT NULL,
  load_status  text NOT NULL CHECK (load_status IN ('loaded', 'failed', 'missing')),
  load_error   text CHECK (length(load_error) <= 2000),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE workspace_plugins (
  workspace_id            uuid NOT NULL REFERENCES workspaces ON DELETE CASCADE,
  plugin_id               text NOT NULL REFERENCES plugins,
  enabled                 boolean NOT NULL DEFAULT false,
  settings                jsonb NOT NULL DEFAULT '{}',
  settings_schema_version integer NOT NULL CHECK (settings_schema_version >= 1),
  enabled_by              uuid REFERENCES users ON DELETE SET NULL,
  enabled_at              timestamptz,
  updated_at              timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id, plugin_id),
  CHECK (octet_length(settings::text) <= 65536)
);

CREATE TABLE plugin_app_registrations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plugin_id          text NOT NULL REFERENCES plugins,
  instance_host      text NOT NULL
                     CHECK (instance_host = lower(instance_host) AND length(instance_host) BETWEEN 1 AND 253),
  credentials_source text NOT NULL CHECK (credentials_source IN ('stored', 'operator_config')),
  client_credentials text,                       -- encrypted
  redirect_uri       text NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plugin_id, instance_host),
  UNIQUE (id, plugin_id),
  CHECK ((credentials_source = 'stored') = (client_credentials IS NOT NULL))
);

CREATE TABLE social_accounts (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id               uuid NOT NULL REFERENCES workspaces,
  plugin_id                  text NOT NULL REFERENCES plugins,
  plugin_app_registration_id uuid NOT NULL,
  provider_account_id        text NOT NULL CHECK (length(provider_account_id) BETWEEN 1 AND 255),
  display_name               text NOT NULL CHECK (length(display_name) <= 255),
  handle                     text CHECK (length(handle) <= 255),
  profile_url                text CHECK (length(profile_url) <= 2048),
  account_type               text CHECK (length(account_type) <= 64),
  credentials                text,                 -- encrypted: OAuth tokens or app password
  credentials_version        integer NOT NULL DEFAULT 0 CHECK (credentials_version >= 0),
  granted_scopes             text[] NOT NULL DEFAULT '{}',
  credentials_expires_at     timestamptz,
  connection_status          text NOT NULL CHECK (connection_status IN
                               ('connected', 'reauthorization_required', 'disconnected', 'plugin_unavailable')),
  capabilities               jsonb,
  capabilities_fetched_at    timestamptz,
  connected_by               uuid REFERENCES users ON DELETE SET NULL,
  connected_at               timestamptz NOT NULL DEFAULT now(),
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, plugin_app_registration_id, provider_account_id),
  UNIQUE (id, workspace_id),
  FOREIGN KEY (plugin_app_registration_id, plugin_id)
    REFERENCES plugin_app_registrations (id, plugin_id),
  CHECK (connection_status <> 'connected' OR credentials IS NOT NULL)
);
CREATE INDEX social_accounts_registration_provider_idx
  ON social_accounts (plugin_app_registration_id, provider_account_id);

CREATE TABLE credential_refresh_leases (
  social_account_id uuid PRIMARY KEY REFERENCES social_accounts ON DELETE CASCADE,
  lease_owner       text NOT NULL CHECK (length(lease_owner) <= 200),
  acquired_at       timestamptz NOT NULL DEFAULT now(),
  lease_expires_at  timestamptz NOT NULL,
  CHECK (lease_expires_at > acquired_at)
);

CREATE TABLE oauth_states (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  state_digest                  bytea NOT NULL UNIQUE CHECK (octet_length(state_digest) = 32),
  session_id                    uuid NOT NULL REFERENCES sessions ON DELETE CASCADE,
  user_id                       uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  workspace_id                  uuid NOT NULL REFERENCES workspaces ON DELETE CASCADE,
  plugin_app_registration_id    uuid NOT NULL REFERENCES plugin_app_registrations,
  reauthorize_social_account_id uuid,
  pkce_verifier                 text,              -- encrypted
  created_at                    timestamptz NOT NULL DEFAULT now(),
  expires_at                    timestamptz NOT NULL,
  consumed_at                   timestamptz,
  FOREIGN KEY (reauthorize_social_account_id, workspace_id)
    REFERENCES social_accounts (id, workspace_id) ON DELETE CASCADE,
  CHECK (expires_at <= created_at + interval '10 minutes')
);
CREATE INDEX oauth_states_expires_at_idx ON oauth_states (expires_at);

CREATE TABLE store_accounts (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id            uuid NOT NULL REFERENCES workspaces,
  plugin_id               text NOT NULL REFERENCES plugins,
  provider_store_id       text NOT NULL CHECK (length(provider_store_id) BETWEEN 1 AND 255),
  display_name            text NOT NULL CHECK (length(display_name) <= 255),
  store_url               text CHECK (length(store_url) <= 2048),
  credentials             text,                    -- encrypted API key or OAuth tokens
  credentials_version     integer NOT NULL DEFAULT 0 CHECK (credentials_version >= 0),
  connection_status       text NOT NULL CHECK (connection_status IN
                            ('connected', 'reauthorization_required', 'disconnected', 'plugin_unavailable')),
  fee_settings            jsonb NOT NULL DEFAULT '{}',   -- validated against the addon's settings
  addon_state             jsonb NOT NULL DEFAULT '{}',   -- import cursors
  addon_state_version     integer NOT NULL DEFAULT 1 CHECK (addon_state_version >= 1),
  last_import_at          timestamptz,
  last_import_error       text CHECK (length(last_import_error) <= 1000),
  next_import_at          timestamptz,
  connected_by            uuid REFERENCES users ON DELETE SET NULL,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, plugin_id, provider_store_id),
  UNIQUE (id, workspace_id),
  CHECK (connection_status <> 'connected' OR credentials IS NOT NULL),
  CHECK (octet_length(addon_state::text) <= 65536 AND octet_length(fee_settings::text) <= 8192)
);
CREATE INDEX store_accounts_import_due_idx ON store_accounts (next_import_at) WHERE connection_status = 'connected';

CREATE TABLE webhook_endpoints (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plugin_id                  text NOT NULL REFERENCES plugins,
  social_account_id          uuid REFERENCES social_accounts ON DELETE CASCADE,
  store_account_id           uuid REFERENCES store_accounts ON DELETE CASCADE,
  plugin_app_registration_id uuid REFERENCES plugin_app_registrations,
  token_digest               bytea NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
  webhook_secret             text NOT NULL,        -- encrypted
  state                      text NOT NULL CHECK (state IN ('active', 'rotating', 'revoked')),
  rotation_ends_at           timestamptz,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(social_account_id, store_account_id, plugin_app_registration_id) = 1),
  CHECK ((state = 'rotating') = (rotation_ends_at IS NOT NULL))
);

CREATE TABLE webhook_events (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_endpoint_id        uuid NOT NULL REFERENCES webhook_endpoints ON DELETE CASCADE,
  -- Deduplication scope: the app registration for social events, the store account for store events.
  plugin_app_registration_id uuid REFERENCES plugin_app_registrations,
  store_account_id           uuid REFERENCES store_accounts ON DELETE CASCADE,
  provider_event_id          text NOT NULL CHECK (length(provider_event_id) BETWEEN 1 AND 255),
  outcome                    text NOT NULL CHECK (outcome IN ('queued', 'ignored', 'failed')),
  received_at                timestamptz NOT NULL DEFAULT now(),
  processed_at               timestamptz,
  CHECK (num_nonnulls(plugin_app_registration_id, store_account_id) = 1)
);
CREATE UNIQUE INDEX webhook_events_registration_dedupe_key
  ON webhook_events (plugin_app_registration_id, provider_event_id) WHERE plugin_app_registration_id IS NOT NULL;
CREATE UNIQUE INDEX webhook_events_store_dedupe_key
  ON webhook_events (store_account_id, provider_event_id) WHERE store_account_id IS NOT NULL;
CREATE INDEX webhook_events_received_at_idx ON webhook_events (received_at);

CREATE TABLE plugin_records (
  social_account_id uuid NOT NULL REFERENCES social_accounts ON DELETE CASCADE,
  plugin_id         text NOT NULL REFERENCES plugins,
  schema_version    integer NOT NULL CHECK (schema_version >= 1),
  data              jsonb NOT NULL DEFAULT '{}',
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (social_account_id, plugin_id),
  CHECK (octet_length(data::text) <= 65536)
);

CREATE TABLE provider_throttles (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plugin_id        text NOT NULL REFERENCES plugins,
  scope            text NOT NULL CHECK (scope IN ('account', 'provider', 'provider_app')),
  scope_key        text NOT NULL,   -- social_account id, '' for provider, registration id for provider_app
  retry_at         timestamptz,
  quota_remaining  integer CHECK (quota_remaining >= 0),
  quota_resets_at  timestamptz,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plugin_id, scope, scope_key),
  CHECK ((scope = 'provider') = (scope_key = ''))
);

CREATE TABLE provider_usage (
  plugin_id             text NOT NULL REFERENCES plugins,
  period_start          date NOT NULL CHECK (extract(day FROM period_start) = 1),
  billable_requests     bigint NOT NULL DEFAULT 0 CHECK (billable_requests >= 0),
  reserved_cost_micros  bigint NOT NULL DEFAULT 0 CHECK (reserved_cost_micros >= 0),
  committed_cost_micros bigint NOT NULL DEFAULT 0 CHECK (committed_cost_micros >= 0),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (plugin_id, period_start)
);

-- ---------------------------------------------------------------------------
-- Media
-- ---------------------------------------------------------------------------

CREATE TABLE media_assets (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id               uuid NOT NULL REFERENCES workspaces,
  kind                       text NOT NULL CHECK (kind IN ('original', 'variant')),
  source_asset_id            uuid,
  source_protection_declared boolean,
  variant_key                text CHECK (length(variant_key) <= 128),
  state                      text NOT NULL CHECK (state IN
                               ('uploading', 'uploaded', 'validating', 'ready', 'rejected', 'failed', 'expired')),
  byte_size                  bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 268435456),
  sha256                     bytea CHECK (octet_length(sha256) = 32),
  declared_content_type      text CHECK (length(declared_content_type) <= 255),
  content_type               text CHECK (length(content_type) <= 255),   -- verified by processor
  media_kind                 text CHECK (media_kind IN ('image', 'video', 'audio')),
  metadata                   jsonb,                                     -- sanitized probe results
  original_filename          text CHECK (length(original_filename) <= 255),
  rejection_code             text CHECK (length(rejection_code) <= 64),
  protection_declared        boolean NOT NULL DEFAULT false,
  protection_tool            text CHECK (length(protection_tool) <= 100),
  protection_declared_by     uuid REFERENCES users ON DELETE SET NULL,
  protection_declared_at     timestamptz,
  uploaded_by                uuid REFERENCES users ON DELETE SET NULL,
  gc_marked_at               timestamptz,
  ready_at                   timestamptz,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, workspace_id),
  UNIQUE (id, workspace_id, protection_declared),
  -- A variant's source must be in the same workspace and must not be declared protected.
  FOREIGN KEY (source_asset_id, workspace_id, source_protection_declared)
    REFERENCES media_assets (id, workspace_id, protection_declared),
  CHECK ((kind = 'variant') = (source_asset_id IS NOT NULL)),
  CHECK (kind = 'original' OR (variant_key IS NOT NULL AND source_protection_declared = false)),
  CHECK (kind = 'variant' OR (variant_key IS NULL AND source_protection_declared IS NULL)),
  CHECK (state IN ('uploading', 'rejected', 'failed', 'expired') OR sha256 IS NOT NULL),
  CHECK (state <> 'ready' OR (content_type IS NOT NULL AND media_kind IS NOT NULL AND ready_at IS NOT NULL)),
  CHECK (state <> 'rejected' OR rejection_code IS NOT NULL),
  CHECK (protection_declared = (protection_declared_at IS NOT NULL)),
  CHECK (NOT protection_declared OR (kind = 'original' AND (media_kind IS NULL OR media_kind = 'image')))
);
CREATE INDEX media_assets_workspace_created_idx ON media_assets (workspace_id, created_at DESC);
CREATE UNIQUE INDEX media_assets_variant_key
  ON media_assets (source_asset_id, variant_key)
  WHERE kind = 'variant' AND state NOT IN ('failed', 'expired');
CREATE UNIQUE INDEX media_assets_dedupe_key
  ON media_assets (workspace_id, sha256, protection_declared)
  WHERE kind = 'original' AND state = 'ready';
CREATE INDEX media_assets_gc_idx ON media_assets (gc_marked_at) WHERE gc_marked_at IS NOT NULL;

CREATE TABLE media_chunks (
  media_asset_id uuid NOT NULL REFERENCES media_assets ON DELETE CASCADE,
  seq            integer NOT NULL CHECK (seq BETWEEN 0 AND 131071),
  data           bytea NOT NULL CHECK (octet_length(data) BETWEEN 1 AND 8388608),
  PRIMARY KEY (media_asset_id, seq)
);
ALTER TABLE media_chunks ALTER COLUMN data SET STORAGE EXTERNAL;

CREATE TABLE upload_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    uuid NOT NULL,
  media_asset_id  uuid NOT NULL UNIQUE,
  user_id         uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  expected_size   bigint NOT NULL CHECK (expected_size BETWEEN 1 AND 268435456),
  chunk_size      integer NOT NULL CHECK (chunk_size BETWEEN 262144 AND 8388608),
  expected_chunks integer GENERATED ALWAYS AS
                    (((expected_size + chunk_size - 1) / chunk_size)::integer) STORED,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  completed_at    timestamptz,
  FOREIGN KEY (media_asset_id, workspace_id)
    REFERENCES media_assets (id, workspace_id) ON DELETE CASCADE
);
CREATE INDEX upload_sessions_open_user_idx ON upload_sessions (user_id) WHERE completed_at IS NULL;
CREATE INDEX upload_sessions_open_expiry_idx ON upload_sessions (expires_at) WHERE completed_at IS NULL;

CREATE TABLE processing_requests (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id       uuid NOT NULL,
  source_asset_id    uuid NOT NULL,
  operation          text NOT NULL CHECK (operation IN
                       ('transcode', 'resize', 'thumbnail', 'extract_audio', 'trim', 'remux', 'metadata')),
  parameters         jsonb NOT NULL DEFAULT '{}',
  output_format      text NOT NULL CHECK (length(output_format) <= 16),
  variant_key        text NOT NULL CHECK (length(variant_key) <= 128),
  idempotency_key    text NOT NULL UNIQUE CHECK (length(idempotency_key) BETWEEN 16 AND 128),
  state              text NOT NULL CHECK (state IN
                       ('pending', 'submitting', 'submitted', 'downloading', 'completed', 'failed', 'abandoned')),
  remote_instance_id text CHECK (length(remote_instance_id) <= 128),
  remote_job_id      text CHECK (length(remote_job_id) <= 128),
  result_asset_id    uuid,
  error_code         text CHECK (length(error_code) <= 64),
  retryable          boolean,
  attempt_count      integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at    timestamptz,
  remote_deleted_at  timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz,
  FOREIGN KEY (source_asset_id, workspace_id) REFERENCES media_assets (id, workspace_id),
  FOREIGN KEY (result_asset_id, workspace_id) REFERENCES media_assets (id, workspace_id),
  CHECK (state <> 'completed' OR result_asset_id IS NOT NULL OR operation = 'metadata'),
  CHECK (state <> 'failed' OR error_code IS NOT NULL)
);
CREATE UNIQUE INDEX processing_requests_active_variant_key
  ON processing_requests (source_asset_id, variant_key)
  WHERE state NOT IN ('failed', 'abandoned');
CREATE INDEX processing_requests_due_idx
  ON processing_requests (next_attempt_at)
  WHERE state IN ('pending', 'submitting', 'submitted', 'downloading');
CREATE INDEX processing_requests_remote_cleanup_idx
  ON processing_requests (updated_at)
  WHERE remote_job_id IS NOT NULL AND remote_deleted_at IS NULL
    AND state IN ('completed', 'failed', 'abandoned');

-- ---------------------------------------------------------------------------
-- Posts, targets and queues
-- ---------------------------------------------------------------------------

CREATE TABLE posts (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces,
  body         text NOT NULL DEFAULT '' CHECK (length(body) <= 20000),
  revision     integer NOT NULL DEFAULT 1 CHECK (revision >= 1),
  lock_version integer NOT NULL DEFAULT 0,
  created_by   uuid REFERENCES users ON DELETE SET NULL,
  updated_by   uuid REFERENCES users ON DELETE SET NULL,
  archived_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, workspace_id)
);
CREATE INDEX posts_workspace_updated_idx ON posts (workspace_id, updated_at DESC) WHERE archived_at IS NULL;

CREATE TABLE post_media (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id   uuid NOT NULL,
  post_id        uuid NOT NULL,
  media_asset_id uuid NOT NULL,
  position       smallint NOT NULL CHECK (position BETWEEN 0 AND 19),
  alt_text       text CHECK (length(alt_text) <= 5000),
  created_at     timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (post_id, workspace_id) REFERENCES posts (id, workspace_id) ON DELETE CASCADE,
  FOREIGN KEY (media_asset_id, workspace_id) REFERENCES media_assets (id, workspace_id),
  CONSTRAINT post_media_position_key UNIQUE (post_id, position) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX post_media_asset_idx ON post_media (media_asset_id);

CREATE TABLE channel_queues (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid NOT NULL,
  social_account_id uuid NOT NULL UNIQUE,
  timezone          text NOT NULL,
  paused            boolean NOT NULL DEFAULT false,
  paused_at         timestamptz,
  paused_by         uuid REFERENCES users ON DELETE SET NULL,
  version           integer NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, social_account_id),
  FOREIGN KEY (social_account_id, workspace_id)
    REFERENCES social_accounts (id, workspace_id) ON DELETE CASCADE,
  CHECK (paused = (paused_at IS NOT NULL))
);

CREATE TABLE queue_slots (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_queue_id uuid NOT NULL REFERENCES channel_queues ON DELETE CASCADE,
  iso_weekday      smallint NOT NULL CHECK (iso_weekday BETWEEN 1 AND 7),   -- 1 = Monday
  local_time       time(0) NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (channel_queue_id, iso_weekday, local_time)
);

CREATE TABLE post_targets (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id                 uuid NOT NULL,
  post_id                      uuid NOT NULL,
  social_account_id            uuid NOT NULL,
  occurrence                   smallint NOT NULL DEFAULT 1 CHECK (occurrence >= 1),
  body_override                text CHECK (length(body_override) <= 20000),
  media_overridden             boolean NOT NULL DEFAULT false,
  provider_options             jsonb NOT NULL DEFAULT '{}',
  mode                         text NOT NULL CHECK (mode IN ('manual', 'queue', 'now')),
  due_at                       timestamptz,
  scheduled_local_at           timestamp,      -- wall-clock input for manual mode
  scheduled_timezone           text,
  scheduled_utc_offset_seconds integer CHECK (scheduled_utc_offset_seconds BETWEEN -64800 AND 64800),
  state                        text NOT NULL CHECK (state IN
                                 ('draft', 'scheduled', 'preparing', 'publishing', 'awaiting_provider',
                                  'published', 'retry_wait', 'blocked', 'needs_attention', 'failed', 'cancelled')),
  attention_reason             text CHECK (attention_reason IN
                                 ('publication_unconfirmed', 'schedule_missed', 'unsupported_checkpoint_version')),
  blocked_reason               text CHECK (blocked_reason IN
                                 ('account_disconnected', 'reauthorization_required', 'plugin_unavailable',
                                  'plugin_disabled', 'validation_failed', 'budget_exhausted',
                                  'protected_media_incompatible', 'media_unavailable', 'fetch_url_unavailable')),
  revision                     integer NOT NULL DEFAULT 1 CHECK (revision >= 1),
  lock_version                 integer NOT NULL DEFAULT 0,
  next_poll_at                 timestamptz,
  retry_at                     timestamptz,
  metrics_next_poll_at         timestamptz,
  metrics_stage                smallint NOT NULL DEFAULT 0 CHECK (metrics_stage >= 0),
  claim_owner                  text CHECK (length(claim_owner) <= 200),
  claim_expires_at             timestamptz,
  fencing_token                bigint NOT NULL DEFAULT 0 CHECK (fencing_token >= 0),
  published_at                 timestamptz,
  remote_post_id               text CHECK (length(remote_post_id) <= 255),
  remote_url                   text CHECK (length(remote_url) <= 2048),
  created_by                   uuid REFERENCES users ON DELETE SET NULL,
  updated_by                   uuid REFERENCES users ON DELETE SET NULL,
  created_at                   timestamptz NOT NULL DEFAULT now(),
  updated_at                   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, social_account_id, occurrence),
  UNIQUE (id, workspace_id),
  UNIQUE (id, social_account_id),
  FOREIGN KEY (post_id, workspace_id) REFERENCES posts (id, workspace_id),
  FOREIGN KEY (social_account_id, workspace_id) REFERENCES social_accounts (id, workspace_id),
  CHECK ((state = 'needs_attention') = (attention_reason IS NOT NULL)),
  CHECK ((state = 'blocked') = (blocked_reason IS NOT NULL)),
  CHECK (state <> 'scheduled' OR due_at IS NOT NULL OR mode = 'queue'),
  CHECK (state <> 'retry_wait' OR retry_at IS NOT NULL),
  CHECK (state <> 'awaiting_provider' OR next_poll_at IS NOT NULL),
  CHECK (state <> 'published' OR published_at IS NOT NULL),
  CHECK (mode <> 'manual' OR state IN ('draft', 'cancelled') OR due_at IS NOT NULL),
  CHECK ((claim_owner IS NULL) = (claim_expires_at IS NULL)),
  CHECK ((scheduled_local_at IS NULL) = (scheduled_timezone IS NULL)),
  CHECK (metrics_next_poll_at IS NULL OR state = 'published')
);
CREATE INDEX post_targets_due_idx ON post_targets (due_at) INCLUDE (social_account_id) WHERE state = 'scheduled';
CREATE INDEX post_targets_poll_idx ON post_targets (next_poll_at) WHERE state = 'awaiting_provider';
CREATE INDEX post_targets_retry_idx ON post_targets (retry_at) WHERE state = 'retry_wait';
CREATE INDEX post_targets_metrics_due_idx ON post_targets (metrics_next_poll_at) WHERE metrics_next_poll_at IS NOT NULL;
CREATE INDEX post_targets_stale_claim_idx ON post_targets (claim_expires_at) WHERE claim_owner IS NOT NULL;
CREATE INDEX post_targets_workspace_state_due_idx ON post_targets (workspace_id, state, due_at);
CREATE INDEX post_targets_account_due_idx ON post_targets (social_account_id, due_at);

CREATE TABLE post_target_media (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id   uuid NOT NULL,
  post_target_id uuid NOT NULL,
  media_asset_id uuid NOT NULL,
  position       smallint NOT NULL CHECK (position BETWEEN 0 AND 19),
  alt_text       text CHECK (length(alt_text) <= 5000),
  created_at     timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (post_target_id, workspace_id) REFERENCES post_targets (id, workspace_id) ON DELETE CASCADE,
  FOREIGN KEY (media_asset_id, workspace_id) REFERENCES media_assets (id, workspace_id),
  CONSTRAINT post_target_media_position_key UNIQUE (post_target_id, position) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX post_target_media_asset_idx ON post_target_media (media_asset_id);

CREATE TABLE queue_entries (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_queue_id   uuid NOT NULL,
  social_account_id  uuid NOT NULL,
  post_target_id     uuid NOT NULL UNIQUE,
  rank               integer NOT NULL CHECK (rank >= 0),
  queue_slot_id      uuid REFERENCES queue_slots ON DELETE SET NULL,
  slot_occurrence_at timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  -- Entry, queue and target must all belong to the same account.
  FOREIGN KEY (channel_queue_id, social_account_id)
    REFERENCES channel_queues (id, social_account_id) ON DELETE CASCADE,
  FOREIGN KEY (post_target_id, social_account_id)
    REFERENCES post_targets (id, social_account_id) ON DELETE CASCADE,
  CONSTRAINT queue_entries_rank_key UNIQUE (channel_queue_id, rank) DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT queue_entries_slot_occurrence_key
    UNIQUE (channel_queue_id, slot_occurrence_at) DEFERRABLE INITIALLY DEFERRED,
  -- The occurrence is the assignment; the slot is only where it came from.
  -- Deleting a slot sets queue_slot_id to NULL and keeps the occurrence.
  CONSTRAINT queue_entries_slot_needs_occurrence CHECK (queue_slot_id IS NULL OR slot_occurrence_at IS NOT NULL)
);

-- ---------------------------------------------------------------------------
-- Delivery
-- ---------------------------------------------------------------------------

CREATE TABLE publish_intents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_target_id  uuid NOT NULL REFERENCES post_targets,
  target_revision integer NOT NULL CHECK (target_revision >= 1),
  kind            text NOT NULL CHECK (kind IN ('scheduled', 'publish_now', 'manual_retry')),
  idempotency_key text NOT NULL UNIQUE CHECK (length(idempotency_key) BETWEEN 16 AND 128),
  state           text NOT NULL CHECK (state IN ('open', 'closed')),
  created_by      uuid REFERENCES users ON DELETE SET NULL,   -- null for scheduled intents
  created_at      timestamptz NOT NULL DEFAULT now(),
  closed_at       timestamptz,
  CHECK ((state = 'closed') = (closed_at IS NOT NULL)),
  CHECK (kind = 'scheduled' OR created_by IS NOT NULL OR state = 'closed')
);
CREATE UNIQUE INDEX publish_intents_one_open_key ON publish_intents (post_target_id) WHERE state = 'open';

CREATE TABLE publish_attempts (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publish_intent_id     uuid NOT NULL REFERENCES publish_intents,
  post_target_id        uuid NOT NULL REFERENCES post_targets,
  attempt_number        integer NOT NULL CHECK (attempt_number >= 1),
  fencing_token         bigint NOT NULL CHECK (fencing_token >= 1),
  plugin_id             text NOT NULL REFERENCES plugins,
  plugin_version        text NOT NULL,
  snapshot              jsonb NOT NULL,                       -- immutable TargetSnapshot
  content_hash          bytea NOT NULL CHECK (octet_length(content_hash) = 32),
  state                 text NOT NULL CHECK (state IN
                          ('claimed', 'submitting', 'pending', 'published', 'not_published',
                           'unknown', 'failed', 'abandoned')),
  delivery_state        text NOT NULL DEFAULT 'not_submitted'
                          CHECK (delivery_state IN ('not_submitted', 'submitted', 'unknown')),
  started_at            timestamptz NOT NULL DEFAULT now(),
  submission_started_at timestamptz,
  finished_at           timestamptz,
  remote_request_id     text CHECK (length(remote_request_id) <= 255),
  remote_post_id        text CHECK (length(remote_post_id) <= 255),
  remote_url            text CHECK (length(remote_url) <= 2048),
  receipt               text,                                 -- encrypted PublishReceipt
  error_class           text CHECK (length(error_class) <= 64),
  provider_code         text CHECK (length(provider_code) <= 128),
  safe_message          text CHECK (length(safe_message) <= 1000),
  retry_at              timestamptz,
  cost_reserved_micros  bigint NOT NULL DEFAULT 0 CHECK (cost_reserved_micros >= 0),
  cost_committed_micros bigint NOT NULL DEFAULT 0 CHECK (cost_committed_micros >= 0),
  UNIQUE (post_target_id, fencing_token),
  UNIQUE (publish_intent_id, attempt_number),
  CHECK (delivery_state = 'not_submitted' OR submission_started_at IS NOT NULL),
  CHECK (state <> 'published' OR remote_post_id IS NOT NULL OR remote_url IS NOT NULL)
);
CREATE INDEX publish_attempts_target_idx ON publish_attempts (post_target_id, started_at DESC);
CREATE INDEX publish_attempts_open_cost_idx ON publish_attempts (plugin_id) WHERE cost_reserved_micros > 0;

CREATE FUNCTION publish_attempts_freeze_snapshot() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.snapshot IS DISTINCT FROM OLD.snapshot
     OR NEW.content_hash IS DISTINCT FROM OLD.content_hash
     OR NEW.publish_intent_id IS DISTINCT FROM OLD.publish_intent_id
     OR NEW.post_target_id IS DISTINCT FROM OLD.post_target_id
     OR NEW.fencing_token IS DISTINCT FROM OLD.fencing_token THEN
    RAISE EXCEPTION 'publish attempt % snapshot and identity are immutable', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER publish_attempts_freeze_snapshot
  BEFORE UPDATE ON publish_attempts
  FOR EACH ROW EXECUTE FUNCTION publish_attempts_freeze_snapshot();

CREATE TABLE publish_attempt_media (
  publish_attempt_id uuid NOT NULL REFERENCES publish_attempts ON DELETE CASCADE,
  position           smallint NOT NULL CHECK (position BETWEEN 0 AND 19),
  media_asset_id     uuid NOT NULL REFERENCES media_assets,
  sha256             bytea NOT NULL CHECK (octet_length(sha256) = 32),
  PRIMARY KEY (publish_attempt_id, position)
);
CREATE INDEX publish_attempt_media_asset_idx ON publish_attempt_media (media_asset_id);

CREATE TABLE remote_media_handles (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid NOT NULL,
  social_account_id uuid NOT NULL,
  media_asset_id    uuid NOT NULL,
  plugin_id         text NOT NULL REFERENCES plugins,
  state             text NOT NULL CHECK (state IN ('pending', 'ready', 'failed', 'expired')),
  handle            text,                                    -- encrypted
  expires_at        timestamptz,
  next_poll_at      timestamptz,
  attempt_count     integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (social_account_id, media_asset_id, plugin_id),
  FOREIGN KEY (social_account_id, workspace_id)
    REFERENCES social_accounts (id, workspace_id) ON DELETE CASCADE,
  FOREIGN KEY (media_asset_id, workspace_id) REFERENCES media_assets (id, workspace_id),
  CHECK (state <> 'ready' OR handle IS NOT NULL),
  CHECK (state <> 'pending' OR next_poll_at IS NOT NULL)
);
CREATE INDEX remote_media_handles_poll_idx ON remote_media_handles (next_poll_at) WHERE state = 'pending';
CREATE INDEX remote_media_handles_asset_idx ON remote_media_handles (media_asset_id);

CREATE TABLE plugin_checkpoints (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plugin_id              text NOT NULL REFERENCES plugins,
  publish_attempt_id     uuid UNIQUE REFERENCES publish_attempts ON DELETE CASCADE,
  remote_media_handle_id uuid UNIQUE REFERENCES remote_media_handles ON DELETE CASCADE,
  schema_version         integer NOT NULL CHECK (schema_version >= 1),
  data                   text NOT NULL,  -- encrypted JSON; plaintext limit 64 KiB enforced by the host
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(publish_attempt_id, remote_media_handle_id) = 1),
  CHECK (octet_length(data) <= 98304)
);

CREATE TABLE signed_media_urls (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id       uuid NOT NULL,
  media_asset_id     uuid NOT NULL,
  publish_attempt_id uuid REFERENCES publish_attempts ON DELETE SET NULL,
  token_digest       bytea NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
  created_at         timestamptz NOT NULL DEFAULT now(),
  expires_at         timestamptz NOT NULL,
  revoked_at         timestamptz,
  fetch_count        integer NOT NULL DEFAULT 0 CHECK (fetch_count >= 0),
  last_fetched_at    timestamptz,
  FOREIGN KEY (media_asset_id, workspace_id) REFERENCES media_assets (id, workspace_id),
  CHECK (expires_at > created_at)
);
CREATE INDEX signed_media_urls_asset_idx ON signed_media_urls (media_asset_id);
CREATE INDEX signed_media_urls_expires_idx ON signed_media_urls (expires_at);

-- ---------------------------------------------------------------------------
-- Dispatch, audit and operations
-- ---------------------------------------------------------------------------

CREATE TABLE outbox_events (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_type     text NOT NULL CHECK (length(event_type) <= 64),
  workspace_id   uuid,
  subject_type   text NOT NULL CHECK (length(subject_type) <= 64),
  subject_id     uuid NOT NULL,
  payload        jsonb NOT NULL DEFAULT '{}',
  created_at     timestamptz NOT NULL DEFAULT now(),
  available_at   timestamptz NOT NULL DEFAULT now(),
  dispatched_at  timestamptz,
  attempt_count  integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error     text CHECK (length(last_error) <= 1000),
  CHECK (octet_length(payload::text) <= 16384)
);
CREATE INDEX outbox_events_pending_idx ON outbox_events (available_at, id) WHERE dispatched_at IS NULL;
CREATE INDEX outbox_events_dispatched_idx ON outbox_events (dispatched_at) WHERE dispatched_at IS NOT NULL;

-- No foreign keys: audit rows outlive the records they describe.
CREATE TABLE audit_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  workspace_id  uuid,
  actor_type    text NOT NULL CHECK (actor_type IN ('user', 'system', 'plugin')),
  actor_user_id uuid,
  actor_label   text NOT NULL CHECK (length(actor_label) <= 200),
  action        text NOT NULL CHECK (length(action) <= 100),
  subject_type  text CHECK (length(subject_type) <= 64),
  subject_id    uuid,
  details       jsonb,                                         -- sanitized changes; never secrets
  request_id    text CHECK (length(request_id) <= 128),
  ip_address    inet,
  CHECK (actor_type <> 'user' OR actor_user_id IS NOT NULL),
  CHECK (details IS NULL OR octet_length(details::text) <= 65536)
);
CREATE INDEX audit_events_workspace_time_idx ON audit_events (workspace_id, occurred_at DESC);
CREATE INDEX audit_events_subject_idx ON audit_events (subject_type, subject_id, occurred_at DESC);
CREATE INDEX audit_events_time_brin ON audit_events USING brin (occurred_at);

CREATE TABLE process_heartbeats (
  process_key  text PRIMARY KEY CHECK (length(process_key) <= 200),
  role         text NOT NULL CHECK (role IN ('web', 'media', 'worker')),
  hostname     text NOT NULL CHECK (length(hostname) <= 255),
  release      text NOT NULL CHECK (length(release) <= 64),
  started_at   timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Stores, tracked links and attribution (09)
-- ---------------------------------------------------------------------------

CREATE TABLE store_products (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        uuid NOT NULL,
  store_account_id    uuid NOT NULL,
  provider_product_id text NOT NULL CHECK (length(provider_product_id) BETWEEN 1 AND 255),
  name                text NOT NULL CHECK (length(name) <= 500),
  url                 text CHECK (length(url) <= 2048),
  currency            char(3) CHECK (currency ~ '^[A-Z]{3}$'),
  list_price_minor    bigint CHECK (list_price_minor >= 0),
  active              boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_account_id, provider_product_id),
  UNIQUE (id, workspace_id),
  FOREIGN KEY (store_account_id, workspace_id) REFERENCES store_accounts (id, workspace_id)
);

CREATE TABLE store_product_stats (
  store_product_id uuid NOT NULL REFERENCES store_products ON DELETE CASCADE,
  day              date NOT NULL,
  page_views       bigint CHECK (page_views >= 0),
  downloads        bigint CHECK (downloads >= 0),
  purchases        bigint CHECK (purchases >= 0),
  PRIMARY KEY (store_product_id, day)
);

-- No buyer personal data is stored (04, commerce addon contract).
CREATE TABLE store_orders (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid NOT NULL,
  store_account_id  uuid NOT NULL,
  provider_order_id text NOT NULL CHECK (length(provider_order_id) BETWEEN 1 AND 255),
  ordered_at        timestamptz NOT NULL,
  status            text NOT NULL CHECK (status IN ('completed', 'refunded', 'partially_refunded')),
  currency          char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  gross_minor       bigint NOT NULL CHECK (gross_minor >= 0),
  refunded_minor    bigint NOT NULL DEFAULT 0 CHECK (refunded_minor >= 0),
  fee_minor         bigint NOT NULL CHECK (fee_minor >= 0),
  fee_estimated     boolean NOT NULL,
  net_minor         bigint GENERATED ALWAYS AS (gross_minor - refunded_minor - fee_minor) STORED,
  codes             text[] NOT NULL DEFAULT '{}',
  imported_at       timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_account_id, provider_order_id),
  UNIQUE (id, workspace_id),
  FOREIGN KEY (store_account_id, workspace_id) REFERENCES store_accounts (id, workspace_id),
  CHECK (refunded_minor <= gross_minor),
  CHECK ((status = 'completed') = (refunded_minor = 0)),
  CHECK (cardinality(codes) <= 10)
);
CREATE INDEX store_orders_workspace_time_idx ON store_orders (workspace_id, ordered_at);

CREATE TABLE store_order_items (
  store_order_id   uuid NOT NULL REFERENCES store_orders ON DELETE CASCADE,
  store_product_id uuid NOT NULL REFERENCES store_products,
  quantity         integer NOT NULL CHECK (quantity >= 1),
  gross_minor      bigint NOT NULL CHECK (gross_minor >= 0),
  PRIMARY KEY (store_order_id, store_product_id)
);
CREATE INDEX store_order_items_product_idx ON store_order_items (store_product_id);

CREATE TABLE attribution_codes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid NOT NULL,
  store_account_id  uuid NOT NULL,
  social_account_id uuid NOT NULL,
  provider_code_id  text CHECK (length(provider_code_id) <= 255),
  code              text NOT NULL CHECK (length(code) BETWEEN 1 AND 64),
  kind              text NOT NULL CHECK (kind IN ('discount', 'affiliate')),
  terms_summary     text CHECK (length(terms_summary) <= 500),
  created_by        uuid REFERENCES users ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  archived_at       timestamptz,
  FOREIGN KEY (store_account_id, workspace_id) REFERENCES store_accounts (id, workspace_id),
  FOREIGN KEY (social_account_id, workspace_id) REFERENCES social_accounts (id, workspace_id)
);
CREATE UNIQUE INDEX attribution_codes_code_key ON attribution_codes (store_account_id, lower(code));

CREATE TABLE tracked_links (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid NOT NULL,
  code              text NOT NULL UNIQUE CHECK (code ~ '^[A-Za-z0-9]{10}$'),
  social_account_id uuid NOT NULL,
  post_target_id    uuid,                 -- null for an account's profile link
  store_product_id  uuid,                 -- null for an approved non-product destination
  destination_url   text NOT NULL CHECK (destination_url ~ '^https://' AND length(destination_url) <= 2048),
  utm_enabled       boolean NOT NULL DEFAULT true,
  created_by        uuid REFERENCES users ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  disabled_at       timestamptz,
  FOREIGN KEY (social_account_id, workspace_id) REFERENCES social_accounts (id, workspace_id),
  -- A post link's target must belong to the same account.
  FOREIGN KEY (post_target_id, social_account_id) REFERENCES post_targets (id, social_account_id),
  FOREIGN KEY (store_product_id, workspace_id) REFERENCES store_products (id, workspace_id)
);
CREATE INDEX tracked_links_target_idx ON tracked_links (post_target_id);
CREATE INDEX tracked_links_product_idx ON tracked_links (store_product_id);
CREATE UNIQUE INDEX tracked_links_profile_key
  ON tracked_links (social_account_id, destination_url) WHERE post_target_id IS NULL AND disabled_at IS NULL;

-- Raw clicks: no IP address, no cookie, referrer host only. Deleted after 90 days (09).
CREATE TABLE link_clicks (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tracked_link_id uuid NOT NULL REFERENCES tracked_links ON DELETE CASCADE,
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  visitor_digest  bytea NOT NULL CHECK (octet_length(visitor_digest) = 16),   -- daily-rotating HMAC
  referrer_host   text CHECK (length(referrer_host) <= 253),
  is_bot          boolean NOT NULL,
  bot_reason      text CHECK (bot_reason IN ('known_agent', 'not_browser', 'publish_burst')),
  CHECK (is_bot = (bot_reason IS NOT NULL))
);
CREATE INDEX link_clicks_link_time_idx ON link_clicks (tracked_link_id, occurred_at);
CREATE INDEX link_clicks_time_brin ON link_clicks USING brin (occurred_at);

CREATE TABLE link_click_daily (
  tracked_link_id uuid NOT NULL REFERENCES tracked_links ON DELETE CASCADE,
  day             date NOT NULL,
  human_clicks    integer NOT NULL DEFAULT 0 CHECK (human_clicks >= 0),
  unique_visitors integer NOT NULL DEFAULT 0 CHECK (unique_visitors >= 0),
  bot_clicks      integer NOT NULL DEFAULT 0 CHECK (bot_clicks >= 0),
  PRIMARY KEY (tracked_link_id, day),
  CHECK (unique_visitors <= human_clicks)
);

CREATE TABLE attribution_allocations (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id          uuid NOT NULL,
  store_order_id        uuid NOT NULL,
  store_product_id      uuid NOT NULL,
  model_version         smallint NOT NULL CHECK (model_version >= 1),
  attribution_method    text NOT NULL CHECK (attribution_method IN ('code', 'click_share', 'unattributed')),
  social_account_id     uuid,
  tracked_link_id       uuid REFERENCES tracked_links ON DELETE SET NULL,
  attribution_code_id   uuid REFERENCES attribution_codes ON DELETE SET NULL,
  share                 numeric(9, 8) NOT NULL CHECK (share > 0 AND share <= 1),
  net_allocated         numeric(18, 4) NOT NULL,      -- in the order's currency, minor units
  currency              char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  computed_at           timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (store_order_id, workspace_id) REFERENCES store_orders (id, workspace_id) ON DELETE CASCADE,
  FOREIGN KEY (store_order_id, store_product_id) REFERENCES store_order_items (store_order_id, store_product_id)
    ON DELETE CASCADE,
  FOREIGN KEY (social_account_id, workspace_id) REFERENCES social_accounts (id, workspace_id),
  CHECK ((attribution_method = 'unattributed') = (social_account_id IS NULL)),
  CHECK (attribution_method <> 'code' OR (attribution_code_id IS NOT NULL AND share = 1)),
  CHECK (attribution_method <> 'click_share' OR tracked_link_id IS NOT NULL),
  CHECK (attribution_method <> 'unattributed' OR (share = 1 AND tracked_link_id IS NULL))
);
CREATE UNIQUE INDEX attribution_allocations_line_key
  ON attribution_allocations (store_order_id, store_product_id, model_version, attribution_method,
    coalesce(tracked_link_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX attribution_allocations_account_idx ON attribution_allocations (social_account_id, model_version);

CREATE TABLE fx_rates (
  currency   char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  rate_date  date NOT NULL,
  per_eur    numeric(20, 10) NOT NULL CHECK (per_eur > 0),   -- units of currency per 1 EUR
  source     text NOT NULL CHECK (length(source) <= 64),
  fetched_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (currency, rate_date)
);

CREATE TABLE cost_entries (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid NOT NULL REFERENCES workspaces,
  social_account_id uuid,                       -- null: platform-wide or workspace-wide
  plugin_id         text REFERENCES plugins,    -- set for platform-wide costs
  period_start      date NOT NULL CHECK (extract(day FROM period_start) = 1),
  amount_minor      bigint NOT NULL CHECK (amount_minor >= 0),
  currency          char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  note              text CHECK (length(note) <= 500),
  created_by        uuid REFERENCES users ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (social_account_id, workspace_id) REFERENCES social_accounts (id, workspace_id)
);
CREATE INDEX cost_entries_workspace_period_idx ON cost_entries (workspace_id, period_start);

-- ---------------------------------------------------------------------------
-- Post metrics (09)
-- ---------------------------------------------------------------------------

CREATE TABLE post_metric_polls (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_target_id uuid NOT NULL REFERENCES post_targets ON DELETE CASCADE,
  stage          smallint NOT NULL CHECK (stage >= 0),
  polled_at      timestamptz NOT NULL DEFAULT now(),
  outcome        text NOT NULL CHECK (outcome IN ('ok', 'unavailable', 'error')),
  error_code     text CHECK (length(error_code) <= 64),
  cost_micros    bigint NOT NULL DEFAULT 0 CHECK (cost_micros >= 0),
  CHECK ((outcome = 'error') = (error_code IS NOT NULL))
);
CREATE INDEX post_metric_polls_target_idx ON post_metric_polls (post_target_id, polled_at);
CREATE INDEX post_metric_polls_cost_idx ON post_metric_polls (polled_at) WHERE cost_micros > 0;

CREATE TABLE post_metric_snapshots (
  post_target_id uuid NOT NULL REFERENCES post_targets ON DELETE CASCADE,
  metric_key     text NOT NULL CHECK (metric_key IN
                   ('views', 'impressions', 'reach', 'likes', 'replies', 'reposts', 'quotes', 'shares',
                    'saves', 'link_clicks', 'avg_watch_seconds', 'total_watch_seconds')),
  captured_at    timestamptz NOT NULL,
  value          numeric(20, 4) NOT NULL CHECK (value >= 0),
  provider_name  text NOT NULL CHECK (length(provider_name) <= 100),
  PRIMARY KEY (post_target_id, metric_key, captured_at)
);

-- ---------------------------------------------------------------------------
-- Relay addons (10)
-- ---------------------------------------------------------------------------

CREATE TABLE integration_tokens (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plugin_id         text NOT NULL REFERENCES plugins,
  link_id           uuid NOT NULL,            -- groups the destinations of one relay link
  purpose           text NOT NULL CHECK (purpose IN ('relay_pull')),
  token_digest      bytea NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
  workspace_id      uuid NOT NULL REFERENCES workspaces,
  created_by        uuid REFERENCES users ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  last_used_at      timestamptz,
  revoked_at        timestamptz
);
CREATE INDEX integration_tokens_link_idx ON integration_tokens (link_id);

CREATE TABLE relay_deliveries (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publish_attempt_id uuid NOT NULL UNIQUE REFERENCES publish_attempts,
  social_account_id  uuid NOT NULL REFERENCES social_accounts,
  link_id            uuid NOT NULL,
  mode               text NOT NULL CHECK (mode IN ('push', 'pull')),
  idempotency_key    text NOT NULL UNIQUE CHECK (length(idempotency_key) BETWEEN 16 AND 128),
  status             text NOT NULL CHECK (status IN
                       ('due', 'leased', 'queued', 'sending', 'delivered', 'failed', 'unknown', 'cancelled')),
  lease_expires_at   timestamptz,
  result             jsonb,                    -- relay's delivery resource, as reported
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CHECK ((status = 'leased') = (lease_expires_at IS NOT NULL)),
  CHECK (mode = 'pull' OR status NOT IN ('due', 'leased')),
  CHECK (status NOT IN ('delivered', 'failed', 'unknown') OR result IS NOT NULL OR status = 'unknown')
);
CREATE INDEX relay_deliveries_pull_due_idx ON relay_deliveries (link_id, created_at) WHERE status = 'due';
CREATE INDEX relay_deliveries_lease_idx ON relay_deliveries (lease_expires_at) WHERE status = 'leased';

-- Single-delivery media URLs served to relays (10).
CREATE TABLE relay_media_grants (
  token_digest       bytea PRIMARY KEY CHECK (octet_length(token_digest) = 32),
  relay_delivery_id  uuid NOT NULL REFERENCES relay_deliveries ON DELETE CASCADE,
  media_asset_id     uuid NOT NULL REFERENCES media_assets,
  expires_at         timestamptz NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at > created_at)
);
CREATE INDEX relay_media_grants_expires_idx ON relay_media_grants (expires_at);

COMMIT;
