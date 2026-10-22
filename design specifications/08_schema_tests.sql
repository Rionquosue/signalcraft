-- Constraint smoke tests for 08_schema.sql. Run against a freshly loaded database:
--   psql -v ON_ERROR_STOP=1 -f 08_schema_tests.sql
-- Each must_fail call must raise; each valid statement must succeed.
-- Everything runs in one transaction and is rolled back.

\pset tuples_only on
\o /dev/null
BEGIN;

CREATE FUNCTION pg_temp.must_fail(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN integrity_constraint_violation OR check_violation OR unique_violation
                 OR foreign_key_violation OR not_null_violation THEN
    RAISE NOTICE 'PASS  %', label;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL  % (statement was accepted)', label;
END $$;

-- Fixtures --------------------------------------------------------------------
INSERT INTO users (id, email, password_digest, display_name) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'owner@example.test', '$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHQ$aGFzaGhhc2g', 'Owner');
INSERT INTO workspaces (id, name, media_quota_bytes) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'Studio', 10737418240),
  ('00000000-0000-0000-0000-0000000000b2', 'Other',  10737418240);
INSERT INTO memberships (workspace_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'owner');
INSERT INTO plugins (plugin_id, kind, version, plugin_api, manifest, load_status) VALUES
  ('bluesky', 'social', '1.0.0', '>=1.2 <2.0', '{}', 'loaded'),
  ('mastodon', 'social', '1.0.0', '>=1.2 <2.0', '{}', 'loaded'),
  ('jinxxy', 'commerce', '1.0.0', '>=1.2 <2.0', '{}', 'loaded');
INSERT INTO plugin_app_registrations (id, plugin_id, instance_host, credentials_source, redirect_uri) VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'bluesky', 'bsky.social', 'operator_config',
   'https://app.example.test/integrations/bluesky/callback');
INSERT INTO social_accounts (id, workspace_id, plugin_id, plugin_app_registration_id,
                             provider_account_id, display_name, credentials, connection_status) VALUES
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', 'bluesky',
   '00000000-0000-0000-0000-0000000000c1', 'did:plc:studio', 'Studio', 'ciphertext', 'connected'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000b2', 'bluesky',
   '00000000-0000-0000-0000-0000000000c1', 'did:plc:other', 'Other', 'ciphertext', 'connected');
INSERT INTO channel_queues (id, workspace_id, social_account_id, timezone) VALUES
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000d1', 'America/Toronto');
INSERT INTO queue_slots (id, channel_queue_id, iso_weekday, local_time) VALUES
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 5, '09:00');
INSERT INTO posts (id, workspace_id, body) VALUES
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000b1', 'Hello');
INSERT INTO post_targets (id, workspace_id, post_id, social_account_id, occurrence, mode, state) VALUES
  ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000d1', 1, 'queue', 'scheduled'),
  ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000d1', 2, 'queue', 'scheduled');
INSERT INTO queue_entries (channel_queue_id, social_account_id, post_target_id, rank, queue_slot_id, slot_occurrence_at) VALUES
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-000000000201', 0, '00000000-0000-0000-0000-0000000000f1', '2026-10-23 13:00Z');

-- Credentials ------------------------------------------------------------------
SELECT pg_temp.must_fail('plaintext password cannot be stored as a digest', $$
  INSERT INTO users (email, password_digest, display_name) VALUES ('a@example.test', 'hunter2', 'A') $$);
SELECT pg_temp.must_fail('unsalted SHA-256 cannot be stored as a digest', $$
  INSERT INTO users (email, password_digest, display_name) VALUES
  ('b@example.test', encode(sha256('hunter2'), 'hex'), 'B') $$);
INSERT INTO users (email, password_digest, display_name) VALUES
  ('c@example.test', '$2a$12$abcdefghijklmnopqrstuuJ0123456789abcdefghijklmnopqrstu', 'C');
DO $$ BEGIN RAISE NOTICE 'PASS  bcrypt fallback hash accepted'; END $$;

-- Tenancy ---------------------------------------------------------------------
SELECT pg_temp.must_fail('target cannot use another workspace''s account', $$
  INSERT INTO post_targets (workspace_id, post_id, social_account_id, mode, state) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-0000000000d2', 'now', 'draft') $$);

-- Scheduling ------------------------------------------------------------------
SELECT pg_temp.must_fail('two queue entries cannot claim one slot occurrence', $$
  INSERT INTO queue_entries (channel_queue_id, social_account_id, post_target_id, rank, queue_slot_id, slot_occurrence_at) VALUES
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-000000000202', 1, '00000000-0000-0000-0000-0000000000f1', '2026-10-23 13:00Z');
  SET CONSTRAINTS ALL IMMEDIATE $$);
SET CONSTRAINTS ALL DEFERRED;

-- Atomic reorder: swapping ranks inside one transaction is allowed by deferred uniqueness.
INSERT INTO queue_entries (channel_queue_id, social_account_id, post_target_id, rank) VALUES
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-000000000202', 1);
UPDATE queue_entries SET rank = 1 - rank;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $$ BEGIN RAISE NOTICE 'PASS  deferred rank swap commits'; END $$;

SELECT pg_temp.must_fail('needs_attention requires a reason', $$
  UPDATE post_targets SET state = 'needs_attention'
  WHERE id = '00000000-0000-0000-0000-000000000201' $$);
SELECT pg_temp.must_fail('blocked requires a reason', $$
  UPDATE post_targets SET state = 'blocked'
  WHERE id = '00000000-0000-0000-0000-000000000201' $$);
SELECT pg_temp.must_fail('manual scheduled target requires due_at', $$
  UPDATE post_targets SET mode = 'manual'
  WHERE id = '00000000-0000-0000-0000-000000000201' $$);
UPDATE post_targets SET state = 'needs_attention', attention_reason = 'schedule_missed'
  WHERE id = '00000000-0000-0000-0000-000000000202';
DO $$ BEGIN RAISE NOTICE 'PASS  needs_attention with reason accepted'; END $$;

-- Delivery --------------------------------------------------------------------
INSERT INTO publish_intents (id, post_target_id, target_revision, kind, idempotency_key, state) VALUES
  ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000201', 1, 'scheduled',
   'intent-key-0000000001', 'open');
SELECT pg_temp.must_fail('only one open publish intent per target', $$
  INSERT INTO publish_intents (post_target_id, target_revision, kind, idempotency_key, state) VALUES
  ('00000000-0000-0000-0000-000000000201', 1, 'scheduled', 'intent-key-0000000002', 'open') $$);

INSERT INTO publish_attempts (id, publish_intent_id, post_target_id, attempt_number, fencing_token,
                              plugin_id, plugin_version, snapshot, content_hash, state) VALUES
  ('00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000301',
   '00000000-0000-0000-0000-000000000201', 1, 1, 'bluesky', '1.0.0', '{"text":"Hello"}',
   decode(repeat('ab', 32), 'hex'), 'claimed');
SELECT pg_temp.must_fail('publish attempt snapshot is immutable', $$
  UPDATE publish_attempts SET snapshot = '{"text":"Changed"}'
  WHERE id = '00000000-0000-0000-0000-000000000401' $$);
UPDATE publish_attempts SET state = 'submitting', delivery_state = 'submitted', submission_started_at = now()
  WHERE id = '00000000-0000-0000-0000-000000000401';
DO $$ BEGIN RAISE NOTICE 'PASS  attempt state may still change'; END $$;
SELECT pg_temp.must_fail('a fencing token is used once per target', $$
  INSERT INTO publish_attempts (publish_intent_id, post_target_id, attempt_number, fencing_token,
                                plugin_id, plugin_version, snapshot, content_hash, state) VALUES
  ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000201', 2, 1,
   'bluesky', '1.0.0', '{}', decode(repeat('ab', 32), 'hex'), 'claimed') $$);
SELECT pg_temp.must_fail('checkpoint must belong to exactly one owner', $$
  INSERT INTO plugin_checkpoints (plugin_id, schema_version, data) VALUES ('bluesky', 1, 'x') $$);

-- Media -----------------------------------------------------------------------
INSERT INTO media_assets (id, workspace_id, kind, state, byte_size, sha256, protection_declared,
                          protection_declared_at, media_kind) VALUES
  ('00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-0000000000b1', 'original',
   'uploaded', 1000, decode(repeat('01', 32), 'hex'), true, now(), 'image'),
  ('00000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-0000000000b1', 'original',
   'uploaded', 1000, decode(repeat('02', 32), 'hex'), false, NULL, 'image');
SELECT pg_temp.must_fail('no variant may be derived from a declared-protected image', $$
  INSERT INTO media_assets (workspace_id, kind, source_asset_id, source_protection_declared, variant_key,
                            state, byte_size) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'variant', '00000000-0000-0000-0000-000000000501', false,
   'resize:1080', 'uploading', 500) $$);
INSERT INTO media_assets (workspace_id, kind, source_asset_id, source_protection_declared, variant_key,
                          state, byte_size) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'variant', '00000000-0000-0000-0000-000000000502', false,
   'resize:1080', 'uploading', 500);
DO $$ BEGIN RAISE NOTICE 'PASS  variant of an unprotected image accepted'; END $$;
SELECT pg_temp.must_fail('cannot declare protection on an image that already has variants', $$
  UPDATE media_assets SET protection_declared = true, protection_declared_at = now()
  WHERE id = '00000000-0000-0000-0000-000000000502' $$);
SELECT pg_temp.must_fail('protection cannot be declared on video', $$
  INSERT INTO media_assets (workspace_id, kind, state, byte_size, sha256, media_kind,
                            protection_declared, protection_declared_at) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'original', 'uploaded', 10, decode(repeat('03', 32), 'hex'),
   'video', true, now()) $$);
SELECT pg_temp.must_fail('variant source must be in the same workspace', $$
  INSERT INTO media_assets (workspace_id, kind, source_asset_id, source_protection_declared, variant_key,
                            state, byte_size) VALUES
  ('00000000-0000-0000-0000-0000000000b2', 'variant', '00000000-0000-0000-0000-000000000502', false,
   'resize:720', 'uploading', 500) $$);
SELECT pg_temp.must_fail('chunk above 8 MiB rejected', $$
  INSERT INTO media_chunks (media_asset_id, seq, data) VALUES
  ('00000000-0000-0000-0000-000000000502', 0, decode(repeat('00', 8388609), 'hex')) $$);
SELECT pg_temp.must_fail('post media cannot reference another workspace''s asset', $$
  INSERT INTO post_media (workspace_id, post_id, media_asset_id, position) VALUES
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000502', 0) $$);

-- Integrations ----------------------------------------------------------------
SELECT pg_temp.must_fail('webhook endpoint binds to exactly one account or registration', $$
  INSERT INTO webhook_endpoints (plugin_id, token_digest, webhook_secret, state) VALUES
  ('bluesky', decode(repeat('07', 32), 'hex'), 'secret', 'active') $$);
INSERT INTO sessions (id, user_id, token_digest, expires_at) VALUES
  ('00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-0000000000a1',
   decode(repeat('09', 32), 'hex'), now() + interval '1 day');
SELECT pg_temp.must_fail('OAuth state lives at most 10 minutes', $$
  INSERT INTO oauth_states (state_digest, session_id, user_id, workspace_id, plugin_app_registration_id, expires_at)
  VALUES (decode(repeat('08', 32), 'hex'), '00000000-0000-0000-0000-000000000601',
          '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
          '00000000-0000-0000-0000-0000000000c1', now() + interval '1 hour') $$);
SELECT pg_temp.must_fail('social account registration must belong to the same plugin', $$
  INSERT INTO social_accounts (workspace_id, plugin_id, plugin_app_registration_id, provider_account_id,
                               display_name, connection_status) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'mastodon', '00000000-0000-0000-0000-0000000000c1', 'x', 'x',
   'disconnected') $$);
SELECT pg_temp.must_fail('provider-scoped throttle has an empty scope key', $$
  INSERT INTO provider_throttles (plugin_id, scope, scope_key) VALUES ('bluesky', 'provider', 'abc') $$);


-- Stores and attribution -------------------------------------------------------
INSERT INTO store_accounts (id, workspace_id, plugin_id, provider_store_id, display_name, credentials, connection_status) VALUES
  ('00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-0000000000b1', 'jinxxy', 'store-1',
   'Studio store', 'ciphertext', 'connected');
INSERT INTO store_products (id, workspace_id, store_account_id, provider_product_id, name, url) VALUES
  ('00000000-0000-0000-0000-000000000702', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-000000000701', 'prod-1', 'Avatar base', 'https://jinxxy.com/studio/avatar');
INSERT INTO store_orders (id, workspace_id, store_account_id, provider_order_id, ordered_at, status, currency,
                          gross_minor, fee_minor, fee_estimated, codes) VALUES
  ('00000000-0000-0000-0000-000000000703', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-000000000701', 'order-1', now(), 'completed', 'USD', 2500, 250, true, '{BSKY10}');
INSERT INTO store_order_items (store_order_id, store_product_id, quantity, gross_minor) VALUES
  ('00000000-0000-0000-0000-000000000703', '00000000-0000-0000-0000-000000000702', 1, 2500);
DO $$ BEGIN
  IF (SELECT net_minor FROM store_orders WHERE id = '00000000-0000-0000-0000-000000000703') <> 2250 THEN
    RAISE EXCEPTION 'FAIL  net revenue is gross - refunds - fees';
  END IF;
  RAISE NOTICE 'PASS  net revenue is gross - refunds - fees';
END $$;
SELECT pg_temp.must_fail('the same store order cannot be imported twice', $$
  INSERT INTO store_orders (workspace_id, store_account_id, provider_order_id, ordered_at, status, currency,
                            gross_minor, fee_minor, fee_estimated) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000701', 'order-1', now(),
   'completed', 'USD', 2500, 250, true) $$);
SELECT pg_temp.must_fail('refund cannot exceed the order amount', $$
  UPDATE store_orders SET status = 'refunded', refunded_minor = 3000
  WHERE id = '00000000-0000-0000-0000-000000000703' $$);
SELECT pg_temp.must_fail('a completed order cannot carry a refund', $$
  UPDATE store_orders SET refunded_minor = 100 WHERE id = '00000000-0000-0000-0000-000000000703' $$);

INSERT INTO tracked_links (id, workspace_id, code, social_account_id, post_target_id, store_product_id, destination_url) VALUES
  ('00000000-0000-0000-0000-000000000704', '00000000-0000-0000-0000-0000000000b1', 'Xy7Pq2LmNa',
   '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000201',
   '00000000-0000-0000-0000-000000000702', 'https://jinxxy.com/studio/avatar');
SELECT pg_temp.must_fail('a tracked link''s target must belong to its account', $$
  INSERT INTO tracked_links (workspace_id, code, social_account_id, post_target_id, destination_url) VALUES
  ('00000000-0000-0000-0000-0000000000b2', 'Ab3Cd4Ef5G', '00000000-0000-0000-0000-0000000000d2',
   '00000000-0000-0000-0000-000000000201', 'https://example.test/') $$);
SELECT pg_temp.must_fail('tracked links only redirect to HTTPS', $$
  INSERT INTO tracked_links (workspace_id, code, social_account_id, destination_url) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'Zz9Yy8Xx7W', '00000000-0000-0000-0000-0000000000d1',
   'javascript:alert(1)') $$);
SELECT pg_temp.must_fail('a bot click must record its reason', $$
  INSERT INTO link_clicks (tracked_link_id, visitor_digest, is_bot) VALUES
  ('00000000-0000-0000-0000-000000000704', decode(repeat('aa', 16), 'hex'), true) $$);

INSERT INTO attribution_codes (id, workspace_id, store_account_id, social_account_id, code, kind) VALUES
  ('00000000-0000-0000-0000-000000000705', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-0000000000d1', 'BSKY10', 'discount');
SELECT pg_temp.must_fail('an attribution code is unique per store regardless of case', $$
  INSERT INTO attribution_codes (workspace_id, store_account_id, social_account_id, code, kind) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000701',
   '00000000-0000-0000-0000-0000000000d1', 'bsky10', 'discount') $$);
INSERT INTO attribution_allocations (workspace_id, store_order_id, store_product_id, model_version, attribution_method,
                                     social_account_id, attribution_code_id, share, net_allocated, currency) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000703',
   '00000000-0000-0000-0000-000000000702', 1, 'code', '00000000-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-000000000705', 1, 2250, 'USD');
DO $$ BEGIN RAISE NOTICE 'PASS  code attribution credits the whole line'; END $$;
SELECT pg_temp.must_fail('code attribution cannot split a line', $$
  INSERT INTO attribution_allocations (workspace_id, store_order_id, store_product_id, model_version, attribution_method,
                                       social_account_id, attribution_code_id, share, net_allocated, currency) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000703',
   '00000000-0000-0000-0000-000000000702', 2, 'code', '00000000-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-000000000705', 0.5, 1125, 'USD') $$);
SELECT pg_temp.must_fail('unattributed allocations name no account', $$
  INSERT INTO attribution_allocations (workspace_id, store_order_id, store_product_id, model_version, attribution_method,
                                       social_account_id, share, net_allocated, currency) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000703',
   '00000000-0000-0000-0000-000000000702', 3, 'unattributed', '00000000-0000-0000-0000-0000000000d1',
   1, 2250, 'USD') $$);
SELECT pg_temp.must_fail('click-share allocations need a tracked link', $$
  INSERT INTO attribution_allocations (workspace_id, store_order_id, store_product_id, model_version, attribution_method,
                                       social_account_id, share, net_allocated, currency) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000703',
   '00000000-0000-0000-0000-000000000702', 4, 'click_share', '00000000-0000-0000-0000-0000000000d1',
   0.4, 900, 'USD') $$);
SELECT pg_temp.must_fail('webhook endpoint cannot bind to both an account and a store', $$
  INSERT INTO webhook_endpoints (plugin_id, social_account_id, store_account_id, token_digest, webhook_secret, state) VALUES
  ('jinxxy', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000701',
   decode(repeat('0a', 32), 'hex'), 'secret', 'active') $$);

-- Metrics ----------------------------------------------------------------------
SELECT pg_temp.must_fail('unknown metric keys are rejected', $$
  INSERT INTO post_metric_snapshots (post_target_id, metric_key, captured_at, value, provider_name) VALUES
  ('00000000-0000-0000-0000-000000000201', 'vibes', now(), 1, 'vibes') $$);
SELECT pg_temp.must_fail('metric values cannot be negative', $$
  INSERT INTO post_metric_snapshots (post_target_id, metric_key, captured_at, value, provider_name) VALUES
  ('00000000-0000-0000-0000-000000000201', 'likes', now(), -1, 'likeCount') $$);
SELECT pg_temp.must_fail('only published targets are polled for metrics', $$
  UPDATE post_targets SET metrics_next_poll_at = now() WHERE id = '00000000-0000-0000-0000-000000000201' $$);

-- Relay ------------------------------------------------------------------------
SELECT pg_temp.must_fail('a leased relay delivery needs a lease expiry', $$
  INSERT INTO relay_deliveries (publish_attempt_id, social_account_id, link_id, mode, idempotency_key, status) VALUES
  ('00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-0000000000d1', gen_random_uuid(), 'pull',
   'relay-key-000000000001', 'leased') $$);
SELECT pg_temp.must_fail('push deliveries are never leased', $$
  INSERT INTO relay_deliveries (publish_attempt_id, social_account_id, link_id, mode, idempotency_key, status,
                                lease_expires_at) VALUES
  ('00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-0000000000d1', gen_random_uuid(), 'push',
   'relay-key-000000000002', 'leased', now() + interval '2 minutes') $$);

DO $$ BEGIN RAISE NOTICE 'ALL TESTS PASSED'; END $$;
ROLLBACK;
