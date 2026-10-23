SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: publish_attempts_freeze_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.publish_attempts_freeze_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: attribution_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attribution_allocations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    store_order_id uuid NOT NULL,
    store_product_id uuid NOT NULL,
    model_version smallint NOT NULL,
    attribution_method text NOT NULL,
    social_account_id uuid,
    tracked_link_id uuid,
    attribution_code_id uuid,
    share numeric(9,8) NOT NULL,
    net_allocated numeric(18,4) NOT NULL,
    currency character(3) NOT NULL,
    computed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT attribution_allocations_attribution_method_check CHECK ((attribution_method = ANY (ARRAY['code'::text, 'click_share'::text, 'unattributed'::text]))),
    CONSTRAINT attribution_allocations_check CHECK (((attribution_method = 'unattributed'::text) = (social_account_id IS NULL))),
    CONSTRAINT attribution_allocations_check1 CHECK (((attribution_method <> 'code'::text) OR ((attribution_code_id IS NOT NULL) AND (share = (1)::numeric)))),
    CONSTRAINT attribution_allocations_check2 CHECK (((attribution_method <> 'click_share'::text) OR (tracked_link_id IS NOT NULL))),
    CONSTRAINT attribution_allocations_check3 CHECK (((attribution_method <> 'unattributed'::text) OR ((share = (1)::numeric) AND (tracked_link_id IS NULL)))),
    CONSTRAINT attribution_allocations_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT attribution_allocations_model_version_check CHECK ((model_version >= 1)),
    CONSTRAINT attribution_allocations_share_check CHECK (((share > (0)::numeric) AND (share <= (1)::numeric)))
);


--
-- Name: attribution_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attribution_codes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    store_account_id uuid NOT NULL,
    social_account_id uuid NOT NULL,
    provider_code_id text,
    code text NOT NULL,
    kind text NOT NULL,
    terms_summary text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    CONSTRAINT attribution_codes_code_check CHECK (((length(code) >= 1) AND (length(code) <= 64))),
    CONSTRAINT attribution_codes_kind_check CHECK ((kind = ANY (ARRAY['discount'::text, 'affiliate'::text]))),
    CONSTRAINT attribution_codes_provider_code_id_check CHECK ((length(provider_code_id) <= 255)),
    CONSTRAINT attribution_codes_terms_summary_check CHECK ((length(terms_summary) <= 500))
);


--
-- Name: audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_events (
    id bigint NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    workspace_id uuid,
    actor_type text NOT NULL,
    actor_user_id uuid,
    actor_label text NOT NULL,
    action text NOT NULL,
    subject_type text,
    subject_id uuid,
    details jsonb,
    request_id text,
    ip_address inet,
    CONSTRAINT audit_events_action_check CHECK ((length(action) <= 100)),
    CONSTRAINT audit_events_actor_label_check CHECK ((length(actor_label) <= 200)),
    CONSTRAINT audit_events_actor_type_check CHECK ((actor_type = ANY (ARRAY['user'::text, 'system'::text, 'plugin'::text]))),
    CONSTRAINT audit_events_check CHECK (((actor_type <> 'user'::text) OR (actor_user_id IS NOT NULL))),
    CONSTRAINT audit_events_details_check CHECK (((details IS NULL) OR (octet_length((details)::text) <= 65536))),
    CONSTRAINT audit_events_request_id_check CHECK ((length(request_id) <= 128)),
    CONSTRAINT audit_events_subject_type_check CHECK ((length(subject_type) <= 64))
);


--
-- Name: audit_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.audit_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: channel_queues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_queues (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    social_account_id uuid NOT NULL,
    timezone text NOT NULL,
    paused boolean DEFAULT false NOT NULL,
    paused_at timestamp with time zone,
    paused_by uuid,
    version integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT channel_queues_check CHECK ((paused = (paused_at IS NOT NULL))),
    CONSTRAINT channel_queues_version_check CHECK ((version >= 0))
);


--
-- Name: cost_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cost_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    social_account_id uuid,
    plugin_id text,
    period_start date NOT NULL,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    note text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cost_entries_amount_minor_check CHECK ((amount_minor >= 0)),
    CONSTRAINT cost_entries_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT cost_entries_note_check CHECK ((length(note) <= 500)),
    CONSTRAINT cost_entries_period_start_check CHECK ((EXTRACT(day FROM period_start) = (1)::numeric))
);


--
-- Name: credential_refresh_leases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_refresh_leases (
    social_account_id uuid NOT NULL,
    lease_owner text NOT NULL,
    acquired_at timestamp with time zone DEFAULT now() NOT NULL,
    lease_expires_at timestamp with time zone NOT NULL,
    CONSTRAINT credential_refresh_leases_check CHECK ((lease_expires_at > acquired_at)),
    CONSTRAINT credential_refresh_leases_lease_owner_check CHECK ((length(lease_owner) <= 200))
);


--
-- Name: fx_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fx_rates (
    currency character(3) NOT NULL,
    rate_date date NOT NULL,
    per_eur numeric(20,10) NOT NULL,
    source text NOT NULL,
    fetched_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fx_rates_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT fx_rates_per_eur_check CHECK ((per_eur > (0)::numeric)),
    CONSTRAINT fx_rates_source_check CHECK ((length(source) <= 64))
);


--
-- Name: integration_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plugin_id text NOT NULL,
    link_id uuid NOT NULL,
    purpose text NOT NULL,
    token_digest bytea NOT NULL,
    workspace_id uuid NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    CONSTRAINT integration_tokens_purpose_check CHECK ((purpose = 'relay_pull'::text)),
    CONSTRAINT integration_tokens_token_digest_check CHECK ((octet_length(token_digest) = 32))
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    email text NOT NULL,
    role text NOT NULL,
    token_digest bytea NOT NULL,
    invited_by uuid,
    expires_at timestamp with time zone NOT NULL,
    accepted_at timestamp with time zone,
    accepted_by uuid,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invitations_check CHECK (((accepted_at IS NULL) OR (revoked_at IS NULL))),
    CONSTRAINT invitations_email_check CHECK (((length(email) >= 3) AND (length(email) <= 320))),
    CONSTRAINT invitations_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'editor'::text, 'viewer'::text]))),
    CONSTRAINT invitations_token_digest_check CHECK ((octet_length(token_digest) = 32))
);


--
-- Name: link_click_daily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.link_click_daily (
    tracked_link_id uuid NOT NULL,
    day date NOT NULL,
    human_clicks integer DEFAULT 0 NOT NULL,
    unique_visitors integer DEFAULT 0 NOT NULL,
    bot_clicks integer DEFAULT 0 NOT NULL,
    CONSTRAINT link_click_daily_bot_clicks_check CHECK ((bot_clicks >= 0)),
    CONSTRAINT link_click_daily_check CHECK ((unique_visitors <= human_clicks)),
    CONSTRAINT link_click_daily_human_clicks_check CHECK ((human_clicks >= 0)),
    CONSTRAINT link_click_daily_unique_visitors_check CHECK ((unique_visitors >= 0))
);


--
-- Name: link_clicks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.link_clicks (
    id bigint NOT NULL,
    tracked_link_id uuid NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    visitor_digest bytea NOT NULL,
    referrer_host text,
    is_bot boolean NOT NULL,
    bot_reason text,
    CONSTRAINT link_clicks_bot_reason_check CHECK ((bot_reason = ANY (ARRAY['known_agent'::text, 'not_browser'::text, 'publish_burst'::text]))),
    CONSTRAINT link_clicks_check CHECK ((is_bot = (bot_reason IS NOT NULL))),
    CONSTRAINT link_clicks_referrer_host_check CHECK ((length(referrer_host) <= 253)),
    CONSTRAINT link_clicks_visitor_digest_check CHECK ((octet_length(visitor_digest) = 16))
);


--
-- Name: link_clicks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.link_clicks ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.link_clicks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: login_throttles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_throttles (
    key_digest bytea NOT NULL,
    scope text NOT NULL,
    window_started_at timestamp with time zone NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT login_throttles_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT login_throttles_key_digest_check CHECK ((octet_length(key_digest) = 32)),
    CONSTRAINT login_throttles_scope_check CHECK ((scope = ANY (ARRAY['email'::text, 'ip'::text])))
);


--
-- Name: media_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.media_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    kind text NOT NULL,
    source_asset_id uuid,
    source_protection_declared boolean,
    variant_key text,
    state text NOT NULL,
    byte_size bigint NOT NULL,
    sha256 bytea,
    declared_content_type text,
    content_type text,
    media_kind text,
    metadata jsonb,
    original_filename text,
    rejection_code text,
    protection_declared boolean DEFAULT false NOT NULL,
    protection_tool text,
    protection_declared_by uuid,
    protection_declared_at timestamp with time zone,
    uploaded_by uuid,
    gc_marked_at timestamp with time zone,
    ready_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT media_assets_byte_size_check CHECK (((byte_size >= 1) AND (byte_size <= 268435456))),
    CONSTRAINT media_assets_check CHECK (((kind = 'variant'::text) = (source_asset_id IS NOT NULL))),
    CONSTRAINT media_assets_check1 CHECK (((kind = 'original'::text) OR ((variant_key IS NOT NULL) AND (source_protection_declared = false)))),
    CONSTRAINT media_assets_check2 CHECK (((kind = 'variant'::text) OR ((variant_key IS NULL) AND (source_protection_declared IS NULL)))),
    CONSTRAINT media_assets_check3 CHECK (((state = ANY (ARRAY['uploading'::text, 'rejected'::text, 'failed'::text, 'expired'::text])) OR (sha256 IS NOT NULL))),
    CONSTRAINT media_assets_check4 CHECK (((state <> 'ready'::text) OR ((content_type IS NOT NULL) AND (media_kind IS NOT NULL) AND (ready_at IS NOT NULL)))),
    CONSTRAINT media_assets_check5 CHECK (((state <> 'rejected'::text) OR (rejection_code IS NOT NULL))),
    CONSTRAINT media_assets_check6 CHECK ((protection_declared = (protection_declared_at IS NOT NULL))),
    CONSTRAINT media_assets_check7 CHECK (((NOT protection_declared) OR ((kind = 'original'::text) AND ((media_kind IS NULL) OR (media_kind = 'image'::text))))),
    CONSTRAINT media_assets_content_type_check CHECK ((length(content_type) <= 255)),
    CONSTRAINT media_assets_declared_content_type_check CHECK ((length(declared_content_type) <= 255)),
    CONSTRAINT media_assets_kind_check CHECK ((kind = ANY (ARRAY['original'::text, 'variant'::text]))),
    CONSTRAINT media_assets_media_kind_check CHECK ((media_kind = ANY (ARRAY['image'::text, 'video'::text, 'audio'::text]))),
    CONSTRAINT media_assets_original_filename_check CHECK ((length(original_filename) <= 255)),
    CONSTRAINT media_assets_protection_tool_check CHECK ((length(protection_tool) <= 100)),
    CONSTRAINT media_assets_rejection_code_check CHECK ((length(rejection_code) <= 64)),
    CONSTRAINT media_assets_sha256_check CHECK ((octet_length(sha256) = 32)),
    CONSTRAINT media_assets_state_check CHECK ((state = ANY (ARRAY['uploading'::text, 'uploaded'::text, 'validating'::text, 'ready'::text, 'rejected'::text, 'failed'::text, 'expired'::text]))),
    CONSTRAINT media_assets_variant_key_check CHECK ((length(variant_key) <= 128))
);


--
-- Name: media_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.media_chunks (
    media_asset_id uuid NOT NULL,
    seq integer NOT NULL,
    data bytea NOT NULL,
    CONSTRAINT media_chunks_data_check CHECK (((octet_length(data) >= 1) AND (octet_length(data) <= 8388608))),
    CONSTRAINT media_chunks_seq_check CHECK (((seq >= 0) AND (seq <= 131071)))
);
ALTER TABLE ONLY public.media_chunks ALTER COLUMN data SET STORAGE EXTERNAL;


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT memberships_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'editor'::text, 'viewer'::text])))
);


--
-- Name: oauth_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_states (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    state_digest bytea NOT NULL,
    session_id uuid NOT NULL,
    user_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    plugin_app_registration_id uuid NOT NULL,
    reauthorize_social_account_id uuid,
    pkce_verifier text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    consumed_at timestamp with time zone,
    CONSTRAINT oauth_states_check CHECK ((expires_at <= (created_at + '00:10:00'::interval))),
    CONSTRAINT oauth_states_state_digest_check CHECK ((octet_length(state_digest) = 32))
);


--
-- Name: outbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_events (
    id bigint NOT NULL,
    event_type text NOT NULL,
    workspace_id uuid,
    subject_type text NOT NULL,
    subject_id uuid NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    available_at timestamp with time zone DEFAULT now() NOT NULL,
    dispatched_at timestamp with time zone,
    attempt_count integer DEFAULT 0 NOT NULL,
    last_error text,
    CONSTRAINT outbox_events_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT outbox_events_event_type_check CHECK ((length(event_type) <= 64)),
    CONSTRAINT outbox_events_last_error_check CHECK ((length(last_error) <= 1000)),
    CONSTRAINT outbox_events_payload_check CHECK ((octet_length((payload)::text) <= 16384)),
    CONSTRAINT outbox_events_subject_type_check CHECK ((length(subject_type) <= 64))
);


--
-- Name: outbox_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.outbox_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.outbox_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: plugin_app_registrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_app_registrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plugin_id text NOT NULL,
    instance_host text NOT NULL,
    credentials_source text NOT NULL,
    client_credentials text,
    redirect_uri text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_app_registrations_check CHECK (((credentials_source = 'stored'::text) = (client_credentials IS NOT NULL))),
    CONSTRAINT plugin_app_registrations_credentials_source_check CHECK ((credentials_source = ANY (ARRAY['stored'::text, 'operator_config'::text]))),
    CONSTRAINT plugin_app_registrations_instance_host_check CHECK (((instance_host = lower(instance_host)) AND ((length(instance_host) >= 1) AND (length(instance_host) <= 253))))
);


--
-- Name: plugin_checkpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_checkpoints (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plugin_id text NOT NULL,
    publish_attempt_id uuid,
    remote_media_handle_id uuid,
    schema_version integer NOT NULL,
    data text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_checkpoints_check CHECK ((num_nonnulls(publish_attempt_id, remote_media_handle_id) = 1)),
    CONSTRAINT plugin_checkpoints_data_check CHECK ((octet_length(data) <= 98304)),
    CONSTRAINT plugin_checkpoints_schema_version_check CHECK ((schema_version >= 1))
);


--
-- Name: plugin_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_records (
    social_account_id uuid NOT NULL,
    plugin_id text NOT NULL,
    schema_version integer NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_records_data_check CHECK ((octet_length((data)::text) <= 65536)),
    CONSTRAINT plugin_records_schema_version_check CHECK ((schema_version >= 1))
);


--
-- Name: plugins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugins (
    plugin_id text NOT NULL,
    kind text NOT NULL,
    version text NOT NULL,
    plugin_api text NOT NULL,
    manifest jsonb NOT NULL,
    load_status text NOT NULL,
    load_error text,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugins_kind_check CHECK ((kind = ANY (ARRAY['social'::text, 'commerce'::text]))),
    CONSTRAINT plugins_load_error_check CHECK ((length(load_error) <= 2000)),
    CONSTRAINT plugins_load_status_check CHECK ((load_status = ANY (ARRAY['loaded'::text, 'failed'::text, 'missing'::text]))),
    CONSTRAINT plugins_plugin_id_check CHECK ((plugin_id ~ '^[a-z][a-z0-9_]{0,63}$'::text))
);


--
-- Name: post_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_media (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    post_id uuid NOT NULL,
    media_asset_id uuid NOT NULL,
    "position" smallint NOT NULL,
    alt_text text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT post_media_alt_text_check CHECK ((length(alt_text) <= 5000)),
    CONSTRAINT post_media_position_check CHECK ((("position" >= 0) AND ("position" <= 19)))
);


--
-- Name: post_metric_polls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_metric_polls (
    id bigint NOT NULL,
    post_target_id uuid NOT NULL,
    stage smallint NOT NULL,
    polled_at timestamp with time zone DEFAULT now() NOT NULL,
    outcome text NOT NULL,
    error_code text,
    cost_micros bigint DEFAULT 0 NOT NULL,
    CONSTRAINT post_metric_polls_check CHECK (((outcome = 'error'::text) = (error_code IS NOT NULL))),
    CONSTRAINT post_metric_polls_cost_micros_check CHECK ((cost_micros >= 0)),
    CONSTRAINT post_metric_polls_error_code_check CHECK ((length(error_code) <= 64)),
    CONSTRAINT post_metric_polls_outcome_check CHECK ((outcome = ANY (ARRAY['ok'::text, 'unavailable'::text, 'error'::text]))),
    CONSTRAINT post_metric_polls_stage_check CHECK ((stage >= 0))
);


--
-- Name: post_metric_polls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.post_metric_polls ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.post_metric_polls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: post_metric_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_metric_snapshots (
    post_target_id uuid NOT NULL,
    metric_key text NOT NULL,
    captured_at timestamp with time zone NOT NULL,
    value numeric(20,4) NOT NULL,
    provider_name text NOT NULL,
    CONSTRAINT post_metric_snapshots_metric_key_check CHECK ((metric_key = ANY (ARRAY['views'::text, 'impressions'::text, 'reach'::text, 'likes'::text, 'replies'::text, 'reposts'::text, 'quotes'::text, 'shares'::text, 'saves'::text, 'link_clicks'::text, 'avg_watch_seconds'::text, 'total_watch_seconds'::text]))),
    CONSTRAINT post_metric_snapshots_provider_name_check CHECK ((length(provider_name) <= 100)),
    CONSTRAINT post_metric_snapshots_value_check CHECK ((value >= (0)::numeric))
);


--
-- Name: post_target_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_target_media (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    post_target_id uuid NOT NULL,
    media_asset_id uuid NOT NULL,
    "position" smallint NOT NULL,
    alt_text text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT post_target_media_alt_text_check CHECK ((length(alt_text) <= 5000)),
    CONSTRAINT post_target_media_position_check CHECK ((("position" >= 0) AND ("position" <= 19)))
);


--
-- Name: post_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_targets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    post_id uuid NOT NULL,
    social_account_id uuid NOT NULL,
    occurrence smallint DEFAULT 1 NOT NULL,
    body_override text,
    media_overridden boolean DEFAULT false NOT NULL,
    provider_options jsonb DEFAULT '{}'::jsonb NOT NULL,
    mode text NOT NULL,
    due_at timestamp with time zone,
    scheduled_local_at timestamp without time zone,
    scheduled_timezone text,
    scheduled_utc_offset_seconds integer,
    state text NOT NULL,
    attention_reason text,
    blocked_reason text,
    revision integer DEFAULT 1 NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    next_poll_at timestamp with time zone,
    retry_at timestamp with time zone,
    metrics_next_poll_at timestamp with time zone,
    metrics_stage smallint DEFAULT 0 NOT NULL,
    claim_owner text,
    claim_expires_at timestamp with time zone,
    fencing_token bigint DEFAULT 0 NOT NULL,
    published_at timestamp with time zone,
    remote_post_id text,
    remote_url text,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT post_targets_attention_reason_check CHECK ((attention_reason = ANY (ARRAY['publication_unconfirmed'::text, 'schedule_missed'::text, 'unsupported_checkpoint_version'::text]))),
    CONSTRAINT post_targets_blocked_reason_check CHECK ((blocked_reason = ANY (ARRAY['account_disconnected'::text, 'reauthorization_required'::text, 'plugin_unavailable'::text, 'plugin_disabled'::text, 'validation_failed'::text, 'budget_exhausted'::text, 'protected_media_incompatible'::text, 'media_unavailable'::text, 'fetch_url_unavailable'::text]))),
    CONSTRAINT post_targets_body_override_check CHECK ((length(body_override) <= 20000)),
    CONSTRAINT post_targets_check CHECK (((state = 'needs_attention'::text) = (attention_reason IS NOT NULL))),
    CONSTRAINT post_targets_check1 CHECK (((state = 'blocked'::text) = (blocked_reason IS NOT NULL))),
    CONSTRAINT post_targets_check2 CHECK (((state <> 'scheduled'::text) OR (due_at IS NOT NULL) OR (mode = 'queue'::text))),
    CONSTRAINT post_targets_check3 CHECK (((state <> 'retry_wait'::text) OR (retry_at IS NOT NULL))),
    CONSTRAINT post_targets_check4 CHECK (((state <> 'awaiting_provider'::text) OR (next_poll_at IS NOT NULL))),
    CONSTRAINT post_targets_check5 CHECK (((state <> 'published'::text) OR (published_at IS NOT NULL))),
    CONSTRAINT post_targets_check6 CHECK (((mode <> 'manual'::text) OR (state = ANY (ARRAY['draft'::text, 'cancelled'::text])) OR (due_at IS NOT NULL))),
    CONSTRAINT post_targets_check7 CHECK (((claim_owner IS NULL) = (claim_expires_at IS NULL))),
    CONSTRAINT post_targets_check8 CHECK (((scheduled_local_at IS NULL) = (scheduled_timezone IS NULL))),
    CONSTRAINT post_targets_check9 CHECK (((metrics_next_poll_at IS NULL) OR (state = 'published'::text))),
    CONSTRAINT post_targets_claim_owner_check CHECK ((length(claim_owner) <= 200)),
    CONSTRAINT post_targets_fencing_token_check CHECK ((fencing_token >= 0)),
    CONSTRAINT post_targets_metrics_stage_check CHECK ((metrics_stage >= 0)),
    CONSTRAINT post_targets_mode_check CHECK ((mode = ANY (ARRAY['manual'::text, 'queue'::text, 'now'::text]))),
    CONSTRAINT post_targets_occurrence_check CHECK ((occurrence >= 1)),
    CONSTRAINT post_targets_remote_post_id_check CHECK ((length(remote_post_id) <= 255)),
    CONSTRAINT post_targets_remote_url_check CHECK ((length(remote_url) <= 2048)),
    CONSTRAINT post_targets_revision_check CHECK ((revision >= 1)),
    CONSTRAINT post_targets_scheduled_utc_offset_seconds_check CHECK (((scheduled_utc_offset_seconds >= '-64800'::integer) AND (scheduled_utc_offset_seconds <= 64800))),
    CONSTRAINT post_targets_state_check CHECK ((state = ANY (ARRAY['draft'::text, 'scheduled'::text, 'preparing'::text, 'publishing'::text, 'awaiting_provider'::text, 'published'::text, 'retry_wait'::text, 'blocked'::text, 'needs_attention'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    revision integer DEFAULT 1 NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_by uuid,
    updated_by uuid,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT posts_body_check CHECK ((length(body) <= 20000)),
    CONSTRAINT posts_revision_check CHECK ((revision >= 1))
);


--
-- Name: process_heartbeats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.process_heartbeats (
    process_key text NOT NULL,
    role text NOT NULL,
    hostname text NOT NULL,
    release text NOT NULL,
    started_at timestamp with time zone NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT process_heartbeats_hostname_check CHECK ((length(hostname) <= 255)),
    CONSTRAINT process_heartbeats_process_key_check CHECK ((length(process_key) <= 200)),
    CONSTRAINT process_heartbeats_release_check CHECK ((length(release) <= 64)),
    CONSTRAINT process_heartbeats_role_check CHECK ((role = ANY (ARRAY['web'::text, 'media'::text, 'worker'::text])))
);


--
-- Name: processing_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processing_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    source_asset_id uuid NOT NULL,
    operation text NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    output_format text NOT NULL,
    variant_key text NOT NULL,
    idempotency_key text NOT NULL,
    state text NOT NULL,
    remote_instance_id text,
    remote_job_id text,
    result_asset_id uuid,
    error_code text,
    retryable boolean,
    attempt_count integer DEFAULT 0 NOT NULL,
    next_attempt_at timestamp with time zone,
    remote_deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT processing_requests_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT processing_requests_check CHECK (((state <> 'completed'::text) OR (result_asset_id IS NOT NULL) OR (operation = 'metadata'::text))),
    CONSTRAINT processing_requests_check1 CHECK (((state <> 'failed'::text) OR (error_code IS NOT NULL))),
    CONSTRAINT processing_requests_error_code_check CHECK ((length(error_code) <= 64)),
    CONSTRAINT processing_requests_idempotency_key_check CHECK (((length(idempotency_key) >= 16) AND (length(idempotency_key) <= 128))),
    CONSTRAINT processing_requests_operation_check CHECK ((operation = ANY (ARRAY['transcode'::text, 'resize'::text, 'thumbnail'::text, 'extract_audio'::text, 'trim'::text, 'remux'::text, 'metadata'::text]))),
    CONSTRAINT processing_requests_output_format_check CHECK ((length(output_format) <= 16)),
    CONSTRAINT processing_requests_remote_instance_id_check CHECK ((length(remote_instance_id) <= 128)),
    CONSTRAINT processing_requests_remote_job_id_check CHECK ((length(remote_job_id) <= 128)),
    CONSTRAINT processing_requests_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'submitting'::text, 'submitted'::text, 'downloading'::text, 'completed'::text, 'failed'::text, 'abandoned'::text]))),
    CONSTRAINT processing_requests_variant_key_check CHECK ((length(variant_key) <= 128))
);


--
-- Name: provider_throttles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_throttles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plugin_id text NOT NULL,
    scope text NOT NULL,
    scope_key text NOT NULL,
    retry_at timestamp with time zone,
    quota_remaining integer,
    quota_resets_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT provider_throttles_check CHECK (((scope = 'provider'::text) = (scope_key = ''::text))),
    CONSTRAINT provider_throttles_quota_remaining_check CHECK ((quota_remaining >= 0)),
    CONSTRAINT provider_throttles_scope_check CHECK ((scope = ANY (ARRAY['account'::text, 'provider'::text, 'provider_app'::text])))
);


--
-- Name: provider_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_usage (
    plugin_id text NOT NULL,
    period_start date NOT NULL,
    billable_requests bigint DEFAULT 0 NOT NULL,
    reserved_cost_micros bigint DEFAULT 0 NOT NULL,
    committed_cost_micros bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT provider_usage_billable_requests_check CHECK ((billable_requests >= 0)),
    CONSTRAINT provider_usage_committed_cost_micros_check CHECK ((committed_cost_micros >= 0)),
    CONSTRAINT provider_usage_period_start_check CHECK ((EXTRACT(day FROM period_start) = (1)::numeric)),
    CONSTRAINT provider_usage_reserved_cost_micros_check CHECK ((reserved_cost_micros >= 0))
);


--
-- Name: publish_attempt_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publish_attempt_media (
    publish_attempt_id uuid NOT NULL,
    "position" smallint NOT NULL,
    media_asset_id uuid NOT NULL,
    sha256 bytea NOT NULL,
    CONSTRAINT publish_attempt_media_position_check CHECK ((("position" >= 0) AND ("position" <= 19))),
    CONSTRAINT publish_attempt_media_sha256_check CHECK ((octet_length(sha256) = 32))
);


--
-- Name: publish_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publish_attempts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    publish_intent_id uuid NOT NULL,
    post_target_id uuid NOT NULL,
    attempt_number integer NOT NULL,
    fencing_token bigint NOT NULL,
    plugin_id text NOT NULL,
    plugin_version text NOT NULL,
    snapshot jsonb NOT NULL,
    content_hash bytea NOT NULL,
    state text NOT NULL,
    delivery_state text DEFAULT 'not_submitted'::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    submission_started_at timestamp with time zone,
    finished_at timestamp with time zone,
    remote_request_id text,
    remote_post_id text,
    remote_url text,
    receipt text,
    error_class text,
    provider_code text,
    safe_message text,
    retry_at timestamp with time zone,
    cost_reserved_micros bigint DEFAULT 0 NOT NULL,
    cost_committed_micros bigint DEFAULT 0 NOT NULL,
    CONSTRAINT publish_attempts_attempt_number_check CHECK ((attempt_number >= 1)),
    CONSTRAINT publish_attempts_check CHECK (((delivery_state = 'not_submitted'::text) OR (submission_started_at IS NOT NULL))),
    CONSTRAINT publish_attempts_check1 CHECK (((state <> 'published'::text) OR (remote_post_id IS NOT NULL) OR (remote_url IS NOT NULL))),
    CONSTRAINT publish_attempts_content_hash_check CHECK ((octet_length(content_hash) = 32)),
    CONSTRAINT publish_attempts_cost_committed_micros_check CHECK ((cost_committed_micros >= 0)),
    CONSTRAINT publish_attempts_cost_reserved_micros_check CHECK ((cost_reserved_micros >= 0)),
    CONSTRAINT publish_attempts_delivery_state_check CHECK ((delivery_state = ANY (ARRAY['not_submitted'::text, 'submitted'::text, 'unknown'::text]))),
    CONSTRAINT publish_attempts_error_class_check CHECK ((length(error_class) <= 64)),
    CONSTRAINT publish_attempts_fencing_token_check CHECK ((fencing_token >= 1)),
    CONSTRAINT publish_attempts_provider_code_check CHECK ((length(provider_code) <= 128)),
    CONSTRAINT publish_attempts_remote_post_id_check CHECK ((length(remote_post_id) <= 255)),
    CONSTRAINT publish_attempts_remote_request_id_check CHECK ((length(remote_request_id) <= 255)),
    CONSTRAINT publish_attempts_remote_url_check CHECK ((length(remote_url) <= 2048)),
    CONSTRAINT publish_attempts_safe_message_check CHECK ((length(safe_message) <= 1000)),
    CONSTRAINT publish_attempts_state_check CHECK ((state = ANY (ARRAY['claimed'::text, 'submitting'::text, 'pending'::text, 'published'::text, 'not_published'::text, 'unknown'::text, 'failed'::text, 'abandoned'::text])))
);


--
-- Name: publish_intents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publish_intents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    post_target_id uuid NOT NULL,
    target_revision integer NOT NULL,
    kind text NOT NULL,
    idempotency_key text NOT NULL,
    state text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    CONSTRAINT publish_intents_check CHECK (((state = 'closed'::text) = (closed_at IS NOT NULL))),
    CONSTRAINT publish_intents_check1 CHECK (((kind = 'scheduled'::text) OR (created_by IS NOT NULL) OR (state = 'closed'::text))),
    CONSTRAINT publish_intents_idempotency_key_check CHECK (((length(idempotency_key) >= 16) AND (length(idempotency_key) <= 128))),
    CONSTRAINT publish_intents_kind_check CHECK ((kind = ANY (ARRAY['scheduled'::text, 'publish_now'::text, 'manual_retry'::text]))),
    CONSTRAINT publish_intents_state_check CHECK ((state = ANY (ARRAY['open'::text, 'closed'::text]))),
    CONSTRAINT publish_intents_target_revision_check CHECK ((target_revision >= 1))
);


--
-- Name: queue_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queue_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_queue_id uuid NOT NULL,
    social_account_id uuid NOT NULL,
    post_target_id uuid NOT NULL,
    rank integer NOT NULL,
    queue_slot_id uuid,
    slot_occurrence_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT queue_entries_check CHECK (((queue_slot_id IS NULL) = (slot_occurrence_at IS NULL))),
    CONSTRAINT queue_entries_rank_check CHECK ((rank >= 0))
);


--
-- Name: queue_slots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queue_slots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_queue_id uuid NOT NULL,
    iso_weekday smallint NOT NULL,
    local_time time(0) without time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT queue_slots_iso_weekday_check CHECK (((iso_weekday >= 1) AND (iso_weekday <= 7)))
);


--
-- Name: relay_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.relay_deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    publish_attempt_id uuid NOT NULL,
    social_account_id uuid NOT NULL,
    link_id uuid NOT NULL,
    mode text NOT NULL,
    idempotency_key text NOT NULL,
    status text NOT NULL,
    lease_expires_at timestamp with time zone,
    result jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT relay_deliveries_check CHECK (((status = 'leased'::text) = (lease_expires_at IS NOT NULL))),
    CONSTRAINT relay_deliveries_check1 CHECK (((mode = 'pull'::text) OR (status <> ALL (ARRAY['due'::text, 'leased'::text])))),
    CONSTRAINT relay_deliveries_check2 CHECK (((status <> ALL (ARRAY['delivered'::text, 'failed'::text, 'unknown'::text])) OR (result IS NOT NULL) OR (status = 'unknown'::text))),
    CONSTRAINT relay_deliveries_idempotency_key_check CHECK (((length(idempotency_key) >= 16) AND (length(idempotency_key) <= 128))),
    CONSTRAINT relay_deliveries_mode_check CHECK ((mode = ANY (ARRAY['push'::text, 'pull'::text]))),
    CONSTRAINT relay_deliveries_status_check CHECK ((status = ANY (ARRAY['due'::text, 'leased'::text, 'queued'::text, 'sending'::text, 'delivered'::text, 'failed'::text, 'unknown'::text, 'cancelled'::text])))
);


--
-- Name: relay_media_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.relay_media_grants (
    token_digest bytea NOT NULL,
    relay_delivery_id uuid NOT NULL,
    media_asset_id uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT relay_media_grants_check CHECK ((expires_at > created_at)),
    CONSTRAINT relay_media_grants_token_digest_check CHECK ((octet_length(token_digest) = 32))
);


--
-- Name: remote_media_handles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.remote_media_handles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    social_account_id uuid NOT NULL,
    media_asset_id uuid NOT NULL,
    plugin_id text NOT NULL,
    state text NOT NULL,
    handle text,
    expires_at timestamp with time zone,
    next_poll_at timestamp with time zone,
    attempt_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT remote_media_handles_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT remote_media_handles_check CHECK (((state <> 'ready'::text) OR (handle IS NOT NULL))),
    CONSTRAINT remote_media_handles_check1 CHECK (((state <> 'pending'::text) OR (next_poll_at IS NOT NULL))),
    CONSTRAINT remote_media_handles_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'ready'::text, 'failed'::text, 'expired'::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token_digest bytea NOT NULL,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT sessions_token_digest_check CHECK ((octet_length(token_digest) = 32)),
    CONSTRAINT sessions_user_agent_check CHECK ((length(user_agent) <= 512))
);


--
-- Name: signed_media_urls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signed_media_urls (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    media_asset_id uuid NOT NULL,
    publish_attempt_id uuid,
    token_digest bytea NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    fetch_count integer DEFAULT 0 NOT NULL,
    last_fetched_at timestamp with time zone,
    CONSTRAINT signed_media_urls_check CHECK ((expires_at > created_at)),
    CONSTRAINT signed_media_urls_fetch_count_check CHECK ((fetch_count >= 0)),
    CONSTRAINT signed_media_urls_token_digest_check CHECK ((octet_length(token_digest) = 32))
);


--
-- Name: social_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.social_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    plugin_id text NOT NULL,
    plugin_app_registration_id uuid NOT NULL,
    provider_account_id text NOT NULL,
    display_name text NOT NULL,
    handle text,
    profile_url text,
    account_type text,
    credentials text,
    credentials_version integer DEFAULT 0 NOT NULL,
    granted_scopes text[] DEFAULT '{}'::text[] NOT NULL,
    credentials_expires_at timestamp with time zone,
    connection_status text NOT NULL,
    capabilities jsonb,
    capabilities_fetched_at timestamp with time zone,
    connected_by uuid,
    connected_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT social_accounts_account_type_check CHECK ((length(account_type) <= 64)),
    CONSTRAINT social_accounts_check CHECK (((connection_status <> 'connected'::text) OR (credentials IS NOT NULL))),
    CONSTRAINT social_accounts_connection_status_check CHECK ((connection_status = ANY (ARRAY['connected'::text, 'reauthorization_required'::text, 'disconnected'::text, 'plugin_unavailable'::text]))),
    CONSTRAINT social_accounts_credentials_version_check CHECK ((credentials_version >= 0)),
    CONSTRAINT social_accounts_display_name_check CHECK ((length(display_name) <= 255)),
    CONSTRAINT social_accounts_handle_check CHECK ((length(handle) <= 255)),
    CONSTRAINT social_accounts_profile_url_check CHECK ((length(profile_url) <= 2048)),
    CONSTRAINT social_accounts_provider_account_id_check CHECK (((length(provider_account_id) >= 1) AND (length(provider_account_id) <= 255)))
);


--
-- Name: solid_queue_batch_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batch_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batch_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batch_executions_id_seq OWNED BY public.solid_queue_batch_executions.id;


--
-- Name: solid_queue_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batches (
    id bigint NOT NULL,
    active_job_batch_id character varying,
    description character varying,
    on_finish text,
    on_success text,
    on_failure text,
    metadata text,
    total_jobs integer DEFAULT 0 NOT NULL,
    completed_jobs integer DEFAULT 0 NOT NULL,
    failed_jobs integer DEFAULT 0 NOT NULL,
    enqueued_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batches_id_seq OWNED BY public.solid_queue_batches.id;


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_blocked_executions_id_seq OWNED BY public.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_claimed_executions_id_seq OWNED BY public.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_failed_executions_id_seq OWNED BY public.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    batch_id bigint
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_jobs_id_seq OWNED BY public.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_pauses_id_seq OWNED BY public.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_processes_id_seq OWNED BY public.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_ready_executions_id_seq OWNED BY public.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_executions_id_seq OWNED BY public.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_tasks_id_seq OWNED BY public.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_scheduled_executions_id_seq OWNED BY public.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_semaphores_id_seq OWNED BY public.solid_queue_semaphores.id;


--
-- Name: store_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    plugin_id text NOT NULL,
    provider_store_id text NOT NULL,
    display_name text NOT NULL,
    store_url text,
    credentials text,
    credentials_version integer DEFAULT 0 NOT NULL,
    connection_status text NOT NULL,
    fee_settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    addon_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    addon_state_version integer DEFAULT 1 NOT NULL,
    last_import_at timestamp with time zone,
    last_import_error text,
    next_import_at timestamp with time zone,
    connected_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT store_accounts_addon_state_version_check CHECK ((addon_state_version >= 1)),
    CONSTRAINT store_accounts_check CHECK (((connection_status <> 'connected'::text) OR (credentials IS NOT NULL))),
    CONSTRAINT store_accounts_check1 CHECK (((octet_length((addon_state)::text) <= 65536) AND (octet_length((fee_settings)::text) <= 8192))),
    CONSTRAINT store_accounts_connection_status_check CHECK ((connection_status = ANY (ARRAY['connected'::text, 'reauthorization_required'::text, 'disconnected'::text, 'plugin_unavailable'::text]))),
    CONSTRAINT store_accounts_credentials_version_check CHECK ((credentials_version >= 0)),
    CONSTRAINT store_accounts_display_name_check CHECK ((length(display_name) <= 255)),
    CONSTRAINT store_accounts_last_import_error_check CHECK ((length(last_import_error) <= 1000)),
    CONSTRAINT store_accounts_provider_store_id_check CHECK (((length(provider_store_id) >= 1) AND (length(provider_store_id) <= 255))),
    CONSTRAINT store_accounts_store_url_check CHECK ((length(store_url) <= 2048))
);


--
-- Name: store_order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_order_items (
    store_order_id uuid NOT NULL,
    store_product_id uuid NOT NULL,
    quantity integer NOT NULL,
    gross_minor bigint NOT NULL,
    CONSTRAINT store_order_items_gross_minor_check CHECK ((gross_minor >= 0)),
    CONSTRAINT store_order_items_quantity_check CHECK ((quantity >= 1))
);


--
-- Name: store_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    store_account_id uuid NOT NULL,
    provider_order_id text NOT NULL,
    ordered_at timestamp with time zone NOT NULL,
    status text NOT NULL,
    currency character(3) NOT NULL,
    gross_minor bigint NOT NULL,
    refunded_minor bigint DEFAULT 0 NOT NULL,
    fee_minor bigint NOT NULL,
    fee_estimated boolean NOT NULL,
    net_minor bigint GENERATED ALWAYS AS (((gross_minor - refunded_minor) - fee_minor)) STORED,
    codes text[] DEFAULT '{}'::text[] NOT NULL,
    imported_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT store_orders_check CHECK ((refunded_minor <= gross_minor)),
    CONSTRAINT store_orders_check1 CHECK (((status = 'completed'::text) = (refunded_minor = 0))),
    CONSTRAINT store_orders_codes_check CHECK ((cardinality(codes) <= 10)),
    CONSTRAINT store_orders_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT store_orders_fee_minor_check CHECK ((fee_minor >= 0)),
    CONSTRAINT store_orders_gross_minor_check CHECK ((gross_minor >= 0)),
    CONSTRAINT store_orders_provider_order_id_check CHECK (((length(provider_order_id) >= 1) AND (length(provider_order_id) <= 255))),
    CONSTRAINT store_orders_refunded_minor_check CHECK ((refunded_minor >= 0)),
    CONSTRAINT store_orders_status_check CHECK ((status = ANY (ARRAY['completed'::text, 'refunded'::text, 'partially_refunded'::text])))
);


--
-- Name: store_product_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_product_stats (
    store_product_id uuid NOT NULL,
    day date NOT NULL,
    page_views bigint,
    downloads bigint,
    purchases bigint,
    CONSTRAINT store_product_stats_downloads_check CHECK ((downloads >= 0)),
    CONSTRAINT store_product_stats_page_views_check CHECK ((page_views >= 0)),
    CONSTRAINT store_product_stats_purchases_check CHECK ((purchases >= 0))
);


--
-- Name: store_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    store_account_id uuid NOT NULL,
    provider_product_id text NOT NULL,
    name text NOT NULL,
    url text,
    currency character(3),
    list_price_minor bigint,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT store_products_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT store_products_list_price_minor_check CHECK ((list_price_minor >= 0)),
    CONSTRAINT store_products_name_check CHECK ((length(name) <= 500)),
    CONSTRAINT store_products_provider_product_id_check CHECK (((length(provider_product_id) >= 1) AND (length(provider_product_id) <= 255))),
    CONSTRAINT store_products_url_check CHECK ((length(url) <= 2048))
);


--
-- Name: tracked_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tracked_links (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    code text NOT NULL,
    social_account_id uuid NOT NULL,
    post_target_id uuid,
    store_product_id uuid,
    destination_url text NOT NULL,
    utm_enabled boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    disabled_at timestamp with time zone,
    CONSTRAINT tracked_links_code_check CHECK ((code ~ '^[A-Za-z0-9]{10}$'::text)),
    CONSTRAINT tracked_links_destination_url_check CHECK (((destination_url ~ '^https://'::text) AND (length(destination_url) <= 2048)))
);


--
-- Name: upload_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.upload_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    media_asset_id uuid NOT NULL,
    user_id uuid NOT NULL,
    expected_size bigint NOT NULL,
    chunk_size integer NOT NULL,
    expected_chunks integer GENERATED ALWAYS AS (((((expected_size + chunk_size) - 1) / chunk_size))::integer) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT upload_sessions_chunk_size_check CHECK (((chunk_size >= 262144) AND (chunk_size <= 8388608))),
    CONSTRAINT upload_sessions_expected_size_check CHECK (((expected_size >= 1) AND (expected_size <= 268435456)))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    password_digest text NOT NULL,
    display_name text NOT NULL,
    timezone text DEFAULT 'America/Toronto'::text NOT NULL,
    disabled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_display_name_check CHECK (((length(display_name) >= 1) AND (length(display_name) <= 100))),
    CONSTRAINT users_email_check CHECK (((length(email) >= 3) AND (length(email) <= 320))),
    CONSTRAINT users_password_digest_check CHECK ((password_digest ~ '^\$(argon2id\$v=19\$|2[aby]\$[0-9]{2}\$)'::text))
);


--
-- Name: webhook_endpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_endpoints (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plugin_id text NOT NULL,
    social_account_id uuid,
    store_account_id uuid,
    plugin_app_registration_id uuid,
    token_digest bytea NOT NULL,
    webhook_secret text NOT NULL,
    state text NOT NULL,
    rotation_ends_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT webhook_endpoints_check CHECK ((num_nonnulls(social_account_id, store_account_id, plugin_app_registration_id) = 1)),
    CONSTRAINT webhook_endpoints_check1 CHECK (((state = 'rotating'::text) = (rotation_ends_at IS NOT NULL))),
    CONSTRAINT webhook_endpoints_state_check CHECK ((state = ANY (ARRAY['active'::text, 'rotating'::text, 'revoked'::text]))),
    CONSTRAINT webhook_endpoints_token_digest_check CHECK ((octet_length(token_digest) = 32))
);


--
-- Name: webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    webhook_endpoint_id uuid NOT NULL,
    plugin_app_registration_id uuid,
    store_account_id uuid,
    provider_event_id text NOT NULL,
    outcome text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    CONSTRAINT webhook_events_check CHECK ((num_nonnulls(plugin_app_registration_id, store_account_id) = 1)),
    CONSTRAINT webhook_events_outcome_check CHECK ((outcome = ANY (ARRAY['queued'::text, 'ignored'::text, 'failed'::text]))),
    CONSTRAINT webhook_events_provider_event_id_check CHECK (((length(provider_event_id) >= 1) AND (length(provider_event_id) <= 255)))
);


--
-- Name: workspace_plugins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_plugins (
    workspace_id uuid NOT NULL,
    plugin_id text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    settings_schema_version integer NOT NULL,
    enabled_by uuid,
    enabled_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT workspace_plugins_settings_check CHECK ((octet_length((settings)::text) <= 65536)),
    CONSTRAINT workspace_plugins_settings_schema_version_check CHECK ((settings_schema_version >= 1))
);


--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    default_timezone text DEFAULT 'America/Toronto'::text NOT NULL,
    media_quota_bytes bigint NOT NULL,
    media_reserved_bytes bigint DEFAULT 0 NOT NULL,
    reporting_currency character(3) DEFAULT 'USD'::bpchar NOT NULL,
    attribution_window_days smallint DEFAULT 7 NOT NULL,
    attribution_half_life_hours integer DEFAULT 48 NOT NULL,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT workspaces_attribution_half_life_hours_check CHECK (((attribution_half_life_hours >= 1) AND (attribution_half_life_hours <= 720))),
    CONSTRAINT workspaces_attribution_window_days_check CHECK (((attribution_window_days >= 1) AND (attribution_window_days <= 30))),
    CONSTRAINT workspaces_media_quota_bytes_check CHECK ((media_quota_bytes > 0)),
    CONSTRAINT workspaces_media_reserved_bytes_check CHECK ((media_reserved_bytes >= 0)),
    CONSTRAINT workspaces_name_check CHECK (((length(name) >= 1) AND (length(name) <= 100))),
    CONSTRAINT workspaces_reporting_currency_check CHECK ((reporting_currency ~ '^[A-Z]{3}$'::text))
);


--
-- Name: solid_queue_batch_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batch_executions_id_seq'::regclass);


--
-- Name: solid_queue_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batches_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: attribution_allocations attribution_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_allocations
    ADD CONSTRAINT attribution_allocations_pkey PRIMARY KEY (id);


--
-- Name: attribution_codes attribution_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_codes
    ADD CONSTRAINT attribution_codes_pkey PRIMARY KEY (id);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: channel_queues channel_queues_id_social_account_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_queues
    ADD CONSTRAINT channel_queues_id_social_account_id_key UNIQUE (id, social_account_id);


--
-- Name: channel_queues channel_queues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_queues
    ADD CONSTRAINT channel_queues_pkey PRIMARY KEY (id);


--
-- Name: channel_queues channel_queues_social_account_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_queues
    ADD CONSTRAINT channel_queues_social_account_id_key UNIQUE (social_account_id);


--
-- Name: cost_entries cost_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_entries
    ADD CONSTRAINT cost_entries_pkey PRIMARY KEY (id);


--
-- Name: credential_refresh_leases credential_refresh_leases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_refresh_leases
    ADD CONSTRAINT credential_refresh_leases_pkey PRIMARY KEY (social_account_id);


--
-- Name: fx_rates fx_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fx_rates
    ADD CONSTRAINT fx_rates_pkey PRIMARY KEY (currency, rate_date);


--
-- Name: integration_tokens integration_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_tokens
    ADD CONSTRAINT integration_tokens_pkey PRIMARY KEY (id);


--
-- Name: integration_tokens integration_tokens_token_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_tokens
    ADD CONSTRAINT integration_tokens_token_digest_key UNIQUE (token_digest);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_token_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_token_digest_key UNIQUE (token_digest);


--
-- Name: link_click_daily link_click_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.link_click_daily
    ADD CONSTRAINT link_click_daily_pkey PRIMARY KEY (tracked_link_id, day);


--
-- Name: link_clicks link_clicks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.link_clicks
    ADD CONSTRAINT link_clicks_pkey PRIMARY KEY (id);


--
-- Name: login_throttles login_throttles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_throttles
    ADD CONSTRAINT login_throttles_pkey PRIMARY KEY (key_digest);


--
-- Name: media_assets media_assets_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: media_assets media_assets_id_workspace_id_protection_declared_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_id_workspace_id_protection_declared_key UNIQUE (id, workspace_id, protection_declared);


--
-- Name: media_assets media_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_pkey PRIMARY KEY (id);


--
-- Name: media_chunks media_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_chunks
    ADD CONSTRAINT media_chunks_pkey PRIMARY KEY (media_asset_id, seq);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_workspace_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_workspace_id_user_id_key UNIQUE (workspace_id, user_id);


--
-- Name: oauth_states oauth_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_states
    ADD CONSTRAINT oauth_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_states oauth_states_state_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_states
    ADD CONSTRAINT oauth_states_state_digest_key UNIQUE (state_digest);


--
-- Name: outbox_events outbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT outbox_events_pkey PRIMARY KEY (id);


--
-- Name: plugin_app_registrations plugin_app_registrations_id_plugin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_app_registrations
    ADD CONSTRAINT plugin_app_registrations_id_plugin_id_key UNIQUE (id, plugin_id);


--
-- Name: plugin_app_registrations plugin_app_registrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_app_registrations
    ADD CONSTRAINT plugin_app_registrations_pkey PRIMARY KEY (id);


--
-- Name: plugin_app_registrations plugin_app_registrations_plugin_id_instance_host_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_app_registrations
    ADD CONSTRAINT plugin_app_registrations_plugin_id_instance_host_key UNIQUE (plugin_id, instance_host);


--
-- Name: plugin_checkpoints plugin_checkpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_checkpoints
    ADD CONSTRAINT plugin_checkpoints_pkey PRIMARY KEY (id);


--
-- Name: plugin_checkpoints plugin_checkpoints_publish_attempt_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_checkpoints
    ADD CONSTRAINT plugin_checkpoints_publish_attempt_id_key UNIQUE (publish_attempt_id);


--
-- Name: plugin_checkpoints plugin_checkpoints_remote_media_handle_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_checkpoints
    ADD CONSTRAINT plugin_checkpoints_remote_media_handle_id_key UNIQUE (remote_media_handle_id);


--
-- Name: plugin_records plugin_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_records
    ADD CONSTRAINT plugin_records_pkey PRIMARY KEY (social_account_id, plugin_id);


--
-- Name: plugins plugins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugins
    ADD CONSTRAINT plugins_pkey PRIMARY KEY (plugin_id);


--
-- Name: post_media post_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_media
    ADD CONSTRAINT post_media_pkey PRIMARY KEY (id);


--
-- Name: post_media post_media_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_media
    ADD CONSTRAINT post_media_position_key UNIQUE (post_id, "position") DEFERRABLE INITIALLY DEFERRED;


--
-- Name: post_metric_polls post_metric_polls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_metric_polls
    ADD CONSTRAINT post_metric_polls_pkey PRIMARY KEY (id);


--
-- Name: post_metric_snapshots post_metric_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_metric_snapshots
    ADD CONSTRAINT post_metric_snapshots_pkey PRIMARY KEY (post_target_id, metric_key, captured_at);


--
-- Name: post_target_media post_target_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_target_media
    ADD CONSTRAINT post_target_media_pkey PRIMARY KEY (id);


--
-- Name: post_target_media post_target_media_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_target_media
    ADD CONSTRAINT post_target_media_position_key UNIQUE (post_target_id, "position") DEFERRABLE INITIALLY DEFERRED;


--
-- Name: post_targets post_targets_id_social_account_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_id_social_account_id_key UNIQUE (id, social_account_id);


--
-- Name: post_targets post_targets_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: post_targets post_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_pkey PRIMARY KEY (id);


--
-- Name: post_targets post_targets_post_id_social_account_id_occurrence_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_post_id_social_account_id_occurrence_key UNIQUE (post_id, social_account_id, occurrence);


--
-- Name: posts posts_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: process_heartbeats process_heartbeats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.process_heartbeats
    ADD CONSTRAINT process_heartbeats_pkey PRIMARY KEY (process_key);


--
-- Name: processing_requests processing_requests_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_requests
    ADD CONSTRAINT processing_requests_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: processing_requests processing_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_requests
    ADD CONSTRAINT processing_requests_pkey PRIMARY KEY (id);


--
-- Name: provider_throttles provider_throttles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_throttles
    ADD CONSTRAINT provider_throttles_pkey PRIMARY KEY (id);


--
-- Name: provider_throttles provider_throttles_plugin_id_scope_scope_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_throttles
    ADD CONSTRAINT provider_throttles_plugin_id_scope_scope_key_key UNIQUE (plugin_id, scope, scope_key);


--
-- Name: provider_usage provider_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_usage
    ADD CONSTRAINT provider_usage_pkey PRIMARY KEY (plugin_id, period_start);


--
-- Name: publish_attempt_media publish_attempt_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempt_media
    ADD CONSTRAINT publish_attempt_media_pkey PRIMARY KEY (publish_attempt_id, "position");


--
-- Name: publish_attempts publish_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempts
    ADD CONSTRAINT publish_attempts_pkey PRIMARY KEY (id);


--
-- Name: publish_attempts publish_attempts_post_target_id_fencing_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempts
    ADD CONSTRAINT publish_attempts_post_target_id_fencing_token_key UNIQUE (post_target_id, fencing_token);


--
-- Name: publish_attempts publish_attempts_publish_intent_id_attempt_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempts
    ADD CONSTRAINT publish_attempts_publish_intent_id_attempt_number_key UNIQUE (publish_intent_id, attempt_number);


--
-- Name: publish_intents publish_intents_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_intents
    ADD CONSTRAINT publish_intents_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: publish_intents publish_intents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_intents
    ADD CONSTRAINT publish_intents_pkey PRIMARY KEY (id);


--
-- Name: queue_entries queue_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_entries
    ADD CONSTRAINT queue_entries_pkey PRIMARY KEY (id);


--
-- Name: queue_entries queue_entries_post_target_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_entries
    ADD CONSTRAINT queue_entries_post_target_id_key UNIQUE (post_target_id);


--
-- Name: queue_entries queue_entries_rank_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_entries
    ADD CONSTRAINT queue_entries_rank_key UNIQUE (channel_queue_id, rank) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: queue_entries queue_entries_slot_occurrence_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_entries
    ADD CONSTRAINT queue_entries_slot_occurrence_key UNIQUE (channel_queue_id, slot_occurrence_at) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: queue_slots queue_slots_channel_queue_id_iso_weekday_local_time_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_slots
    ADD CONSTRAINT queue_slots_channel_queue_id_iso_weekday_local_time_key UNIQUE (channel_queue_id, iso_weekday, local_time);


--
-- Name: queue_slots queue_slots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_slots
    ADD CONSTRAINT queue_slots_pkey PRIMARY KEY (id);


--
-- Name: relay_deliveries relay_deliveries_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_deliveries
    ADD CONSTRAINT relay_deliveries_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: relay_deliveries relay_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_deliveries
    ADD CONSTRAINT relay_deliveries_pkey PRIMARY KEY (id);


--
-- Name: relay_deliveries relay_deliveries_publish_attempt_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_deliveries
    ADD CONSTRAINT relay_deliveries_publish_attempt_id_key UNIQUE (publish_attempt_id);


--
-- Name: relay_media_grants relay_media_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_media_grants
    ADD CONSTRAINT relay_media_grants_pkey PRIMARY KEY (token_digest);


--
-- Name: remote_media_handles remote_media_handles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote_media_handles
    ADD CONSTRAINT remote_media_handles_pkey PRIMARY KEY (id);


--
-- Name: remote_media_handles remote_media_handles_social_account_id_media_asset_id_plugi_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote_media_handles
    ADD CONSTRAINT remote_media_handles_social_account_id_media_asset_id_plugi_key UNIQUE (social_account_id, media_asset_id, plugin_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_token_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_token_digest_key UNIQUE (token_digest);


--
-- Name: signed_media_urls signed_media_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signed_media_urls
    ADD CONSTRAINT signed_media_urls_pkey PRIMARY KEY (id);


--
-- Name: signed_media_urls signed_media_urls_token_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signed_media_urls
    ADD CONSTRAINT signed_media_urls_token_digest_key UNIQUE (token_digest);


--
-- Name: social_accounts social_accounts_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: social_accounts social_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_pkey PRIMARY KEY (id);


--
-- Name: social_accounts social_accounts_workspace_id_plugin_app_registration_id_pro_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_workspace_id_plugin_app_registration_id_pro_key UNIQUE (workspace_id, plugin_app_registration_id, provider_account_id);


--
-- Name: solid_queue_batch_executions solid_queue_batch_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT solid_queue_batch_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batches solid_queue_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches
    ADD CONSTRAINT solid_queue_batches_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: store_accounts store_accounts_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_accounts
    ADD CONSTRAINT store_accounts_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: store_accounts store_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_accounts
    ADD CONSTRAINT store_accounts_pkey PRIMARY KEY (id);


--
-- Name: store_accounts store_accounts_workspace_id_plugin_id_provider_store_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_accounts
    ADD CONSTRAINT store_accounts_workspace_id_plugin_id_provider_store_id_key UNIQUE (workspace_id, plugin_id, provider_store_id);


--
-- Name: store_order_items store_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_order_items
    ADD CONSTRAINT store_order_items_pkey PRIMARY KEY (store_order_id, store_product_id);


--
-- Name: store_orders store_orders_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_orders
    ADD CONSTRAINT store_orders_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: store_orders store_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_orders
    ADD CONSTRAINT store_orders_pkey PRIMARY KEY (id);


--
-- Name: store_orders store_orders_store_account_id_provider_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_orders
    ADD CONSTRAINT store_orders_store_account_id_provider_order_id_key UNIQUE (store_account_id, provider_order_id);


--
-- Name: store_product_stats store_product_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_product_stats
    ADD CONSTRAINT store_product_stats_pkey PRIMARY KEY (store_product_id, day);


--
-- Name: store_products store_products_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_products
    ADD CONSTRAINT store_products_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: store_products store_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_products
    ADD CONSTRAINT store_products_pkey PRIMARY KEY (id);


--
-- Name: store_products store_products_store_account_id_provider_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_products
    ADD CONSTRAINT store_products_store_account_id_provider_product_id_key UNIQUE (store_account_id, provider_product_id);


--
-- Name: tracked_links tracked_links_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_links
    ADD CONSTRAINT tracked_links_code_key UNIQUE (code);


--
-- Name: tracked_links tracked_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_links
    ADD CONSTRAINT tracked_links_pkey PRIMARY KEY (id);


--
-- Name: upload_sessions upload_sessions_media_asset_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_sessions
    ADD CONSTRAINT upload_sessions_media_asset_id_key UNIQUE (media_asset_id);


--
-- Name: upload_sessions upload_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_sessions
    ADD CONSTRAINT upload_sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: webhook_endpoints webhook_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_pkey PRIMARY KEY (id);


--
-- Name: webhook_endpoints webhook_endpoints_token_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_token_digest_key UNIQUE (token_digest);


--
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (id);


--
-- Name: workspace_plugins workspace_plugins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_plugins
    ADD CONSTRAINT workspace_plugins_pkey PRIMARY KEY (workspace_id, plugin_id);


--
-- Name: workspaces workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);


--
-- Name: attribution_allocations_account_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attribution_allocations_account_idx ON public.attribution_allocations USING btree (social_account_id, model_version);


--
-- Name: attribution_allocations_line_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX attribution_allocations_line_key ON public.attribution_allocations USING btree (store_order_id, store_product_id, model_version, attribution_method, COALESCE(tracked_link_id, '00000000-0000-0000-0000-000000000000'::uuid));


--
-- Name: attribution_codes_code_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX attribution_codes_code_key ON public.attribution_codes USING btree (store_account_id, lower(code));


--
-- Name: audit_events_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_events_subject_idx ON public.audit_events USING btree (subject_type, subject_id, occurred_at DESC);


--
-- Name: audit_events_time_brin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_events_time_brin ON public.audit_events USING brin (occurred_at);


--
-- Name: audit_events_workspace_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_events_workspace_time_idx ON public.audit_events USING btree (workspace_id, occurred_at DESC);


--
-- Name: cost_entries_workspace_period_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cost_entries_workspace_period_idx ON public.cost_entries USING btree (workspace_id, period_start);


--
-- Name: index_solid_queue_batch_executions_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batch_executions_on_batch_id ON public.solid_queue_batch_executions USING btree (batch_id);


--
-- Name: index_solid_queue_batch_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batch_executions_on_job_id ON public.solid_queue_batch_executions USING btree (job_id);


--
-- Name: index_solid_queue_batches_on_active_job_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batches_on_active_job_batch_id ON public.solid_queue_batches USING btree (active_job_batch_id);


--
-- Name: index_solid_queue_batches_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batches_on_finished_at ON public.solid_queue_batches USING btree (finished_at);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON public.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON public.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON public.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON public.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON public.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON public.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON public.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON public.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON public.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON public.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_batch_id ON public.solid_queue_jobs USING btree (batch_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON public.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON public.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON public.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON public.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON public.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON public.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON public.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON public.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON public.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON public.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON public.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON public.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON public.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON public.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON public.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON public.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON public.solid_queue_semaphores USING btree (key, value);


--
-- Name: integration_tokens_link_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX integration_tokens_link_idx ON public.integration_tokens USING btree (link_id);


--
-- Name: invitations_open_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX invitations_open_email_key ON public.invitations USING btree (workspace_id, lower(email)) WHERE ((accepted_at IS NULL) AND (revoked_at IS NULL));


--
-- Name: link_clicks_link_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX link_clicks_link_time_idx ON public.link_clicks USING btree (tracked_link_id, occurred_at);


--
-- Name: link_clicks_time_brin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX link_clicks_time_brin ON public.link_clicks USING brin (occurred_at);


--
-- Name: login_throttles_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX login_throttles_updated_at_idx ON public.login_throttles USING btree (updated_at);


--
-- Name: media_assets_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX media_assets_dedupe_key ON public.media_assets USING btree (workspace_id, sha256, protection_declared) WHERE ((kind = 'original'::text) AND (state = 'ready'::text));


--
-- Name: media_assets_gc_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX media_assets_gc_idx ON public.media_assets USING btree (gc_marked_at) WHERE (gc_marked_at IS NOT NULL);


--
-- Name: media_assets_variant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX media_assets_variant_key ON public.media_assets USING btree (source_asset_id, variant_key) WHERE ((kind = 'variant'::text) AND (state <> ALL (ARRAY['failed'::text, 'expired'::text])));


--
-- Name: media_assets_workspace_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX media_assets_workspace_created_idx ON public.media_assets USING btree (workspace_id, created_at DESC);


--
-- Name: memberships_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX memberships_user_id_idx ON public.memberships USING btree (user_id);


--
-- Name: oauth_states_expires_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth_states_expires_at_idx ON public.oauth_states USING btree (expires_at);


--
-- Name: outbox_events_dispatched_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX outbox_events_dispatched_idx ON public.outbox_events USING btree (dispatched_at) WHERE (dispatched_at IS NOT NULL);


--
-- Name: outbox_events_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX outbox_events_pending_idx ON public.outbox_events USING btree (available_at, id) WHERE (dispatched_at IS NULL);


--
-- Name: post_media_asset_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_media_asset_idx ON public.post_media USING btree (media_asset_id);


--
-- Name: post_metric_polls_cost_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_metric_polls_cost_idx ON public.post_metric_polls USING btree (polled_at) WHERE (cost_micros > 0);


--
-- Name: post_metric_polls_target_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_metric_polls_target_idx ON public.post_metric_polls USING btree (post_target_id, polled_at);


--
-- Name: post_target_media_asset_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_target_media_asset_idx ON public.post_target_media USING btree (media_asset_id);


--
-- Name: post_targets_account_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_targets_account_due_idx ON public.post_targets USING btree (social_account_id, due_at);


--
-- Name: post_targets_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_targets_due_idx ON public.post_targets USING btree (due_at) INCLUDE (social_account_id) WHERE (state = 'scheduled'::text);


--
-- Name: post_targets_metrics_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_targets_metrics_due_idx ON public.post_targets USING btree (metrics_next_poll_at) WHERE (metrics_next_poll_at IS NOT NULL);


--
-- Name: post_targets_poll_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_targets_poll_idx ON public.post_targets USING btree (next_poll_at) WHERE (state = 'awaiting_provider'::text);


--
-- Name: post_targets_retry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_targets_retry_idx ON public.post_targets USING btree (retry_at) WHERE (state = 'retry_wait'::text);


--
-- Name: post_targets_stale_claim_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_targets_stale_claim_idx ON public.post_targets USING btree (claim_expires_at) WHERE (claim_owner IS NOT NULL);


--
-- Name: post_targets_workspace_state_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_targets_workspace_state_due_idx ON public.post_targets USING btree (workspace_id, state, due_at);


--
-- Name: posts_workspace_updated_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_workspace_updated_idx ON public.posts USING btree (workspace_id, updated_at DESC) WHERE (archived_at IS NULL);


--
-- Name: processing_requests_active_variant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX processing_requests_active_variant_key ON public.processing_requests USING btree (source_asset_id, variant_key) WHERE (state <> ALL (ARRAY['failed'::text, 'abandoned'::text]));


--
-- Name: processing_requests_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX processing_requests_due_idx ON public.processing_requests USING btree (next_attempt_at) WHERE (state = ANY (ARRAY['pending'::text, 'submitting'::text, 'submitted'::text, 'downloading'::text]));


--
-- Name: processing_requests_remote_cleanup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX processing_requests_remote_cleanup_idx ON public.processing_requests USING btree (updated_at) WHERE ((remote_job_id IS NOT NULL) AND (remote_deleted_at IS NULL) AND (state = ANY (ARRAY['completed'::text, 'failed'::text, 'abandoned'::text])));


--
-- Name: publish_attempt_media_asset_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX publish_attempt_media_asset_idx ON public.publish_attempt_media USING btree (media_asset_id);


--
-- Name: publish_attempts_open_cost_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX publish_attempts_open_cost_idx ON public.publish_attempts USING btree (plugin_id) WHERE (cost_reserved_micros > 0);


--
-- Name: publish_attempts_target_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX publish_attempts_target_idx ON public.publish_attempts USING btree (post_target_id, started_at DESC);


--
-- Name: publish_intents_one_open_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX publish_intents_one_open_key ON public.publish_intents USING btree (post_target_id) WHERE (state = 'open'::text);


--
-- Name: relay_deliveries_lease_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX relay_deliveries_lease_idx ON public.relay_deliveries USING btree (lease_expires_at) WHERE (status = 'leased'::text);


--
-- Name: relay_deliveries_pull_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX relay_deliveries_pull_due_idx ON public.relay_deliveries USING btree (link_id, created_at) WHERE (status = 'due'::text);


--
-- Name: relay_media_grants_expires_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX relay_media_grants_expires_idx ON public.relay_media_grants USING btree (expires_at);


--
-- Name: remote_media_handles_asset_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX remote_media_handles_asset_idx ON public.remote_media_handles USING btree (media_asset_id);


--
-- Name: remote_media_handles_poll_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX remote_media_handles_poll_idx ON public.remote_media_handles USING btree (next_poll_at) WHERE (state = 'pending'::text);


--
-- Name: sessions_expires_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_expires_at_idx ON public.sessions USING btree (expires_at);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_user_id_idx ON public.sessions USING btree (user_id);


--
-- Name: signed_media_urls_asset_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX signed_media_urls_asset_idx ON public.signed_media_urls USING btree (media_asset_id);


--
-- Name: signed_media_urls_expires_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX signed_media_urls_expires_idx ON public.signed_media_urls USING btree (expires_at);


--
-- Name: social_accounts_registration_provider_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX social_accounts_registration_provider_idx ON public.social_accounts USING btree (plugin_app_registration_id, provider_account_id);


--
-- Name: store_accounts_import_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX store_accounts_import_due_idx ON public.store_accounts USING btree (next_import_at) WHERE (connection_status = 'connected'::text);


--
-- Name: store_order_items_product_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX store_order_items_product_idx ON public.store_order_items USING btree (store_product_id);


--
-- Name: store_orders_workspace_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX store_orders_workspace_time_idx ON public.store_orders USING btree (workspace_id, ordered_at);


--
-- Name: tracked_links_product_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tracked_links_product_idx ON public.tracked_links USING btree (store_product_id);


--
-- Name: tracked_links_profile_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tracked_links_profile_key ON public.tracked_links USING btree (social_account_id, destination_url) WHERE ((post_target_id IS NULL) AND (disabled_at IS NULL));


--
-- Name: tracked_links_target_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tracked_links_target_idx ON public.tracked_links USING btree (post_target_id);


--
-- Name: upload_sessions_open_expiry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX upload_sessions_open_expiry_idx ON public.upload_sessions USING btree (expires_at) WHERE (completed_at IS NULL);


--
-- Name: upload_sessions_open_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX upload_sessions_open_user_idx ON public.upload_sessions USING btree (user_id) WHERE (completed_at IS NULL);


--
-- Name: users_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_key ON public.users USING btree (lower(email));


--
-- Name: webhook_events_received_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webhook_events_received_at_idx ON public.webhook_events USING btree (received_at);


--
-- Name: webhook_events_registration_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX webhook_events_registration_dedupe_key ON public.webhook_events USING btree (plugin_app_registration_id, provider_event_id) WHERE (plugin_app_registration_id IS NOT NULL);


--
-- Name: webhook_events_store_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX webhook_events_store_dedupe_key ON public.webhook_events USING btree (store_account_id, provider_event_id) WHERE (store_account_id IS NOT NULL);


--
-- Name: publish_attempts publish_attempts_freeze_snapshot; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER publish_attempts_freeze_snapshot BEFORE UPDATE ON public.publish_attempts FOR EACH ROW EXECUTE FUNCTION public.publish_attempts_freeze_snapshot();


--
-- Name: attribution_allocations attribution_allocations_attribution_code_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_allocations
    ADD CONSTRAINT attribution_allocations_attribution_code_id_fkey FOREIGN KEY (attribution_code_id) REFERENCES public.attribution_codes(id) ON DELETE SET NULL;


--
-- Name: attribution_allocations attribution_allocations_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_allocations
    ADD CONSTRAINT attribution_allocations_social_account_id_workspace_id_fkey FOREIGN KEY (social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id);


--
-- Name: attribution_allocations attribution_allocations_store_order_id_store_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_allocations
    ADD CONSTRAINT attribution_allocations_store_order_id_store_product_id_fkey FOREIGN KEY (store_order_id, store_product_id) REFERENCES public.store_order_items(store_order_id, store_product_id) ON DELETE CASCADE;


--
-- Name: attribution_allocations attribution_allocations_store_order_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_allocations
    ADD CONSTRAINT attribution_allocations_store_order_id_workspace_id_fkey FOREIGN KEY (store_order_id, workspace_id) REFERENCES public.store_orders(id, workspace_id) ON DELETE CASCADE;


--
-- Name: attribution_allocations attribution_allocations_tracked_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_allocations
    ADD CONSTRAINT attribution_allocations_tracked_link_id_fkey FOREIGN KEY (tracked_link_id) REFERENCES public.tracked_links(id) ON DELETE SET NULL;


--
-- Name: attribution_codes attribution_codes_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_codes
    ADD CONSTRAINT attribution_codes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: attribution_codes attribution_codes_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_codes
    ADD CONSTRAINT attribution_codes_social_account_id_workspace_id_fkey FOREIGN KEY (social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id);


--
-- Name: attribution_codes attribution_codes_store_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribution_codes
    ADD CONSTRAINT attribution_codes_store_account_id_workspace_id_fkey FOREIGN KEY (store_account_id, workspace_id) REFERENCES public.store_accounts(id, workspace_id);


--
-- Name: channel_queues channel_queues_paused_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_queues
    ADD CONSTRAINT channel_queues_paused_by_fkey FOREIGN KEY (paused_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: channel_queues channel_queues_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_queues
    ADD CONSTRAINT channel_queues_social_account_id_workspace_id_fkey FOREIGN KEY (social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id) ON DELETE CASCADE;


--
-- Name: cost_entries cost_entries_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_entries
    ADD CONSTRAINT cost_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: cost_entries cost_entries_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_entries
    ADD CONSTRAINT cost_entries_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: cost_entries cost_entries_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_entries
    ADD CONSTRAINT cost_entries_social_account_id_workspace_id_fkey FOREIGN KEY (social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id);


--
-- Name: cost_entries cost_entries_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_entries
    ADD CONSTRAINT cost_entries_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: credential_refresh_leases credential_refresh_leases_social_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_refresh_leases
    ADD CONSTRAINT credential_refresh_leases_social_account_id_fkey FOREIGN KEY (social_account_id) REFERENCES public.social_accounts(id) ON DELETE CASCADE;


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_batch_executions fk_rails_7c5e073422; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_7c5e073422 FOREIGN KEY (batch_id) REFERENCES public.solid_queue_batches(id) ON DELETE CASCADE;


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_batch_executions fk_rails_bc9f981155; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_bc9f981155 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: integration_tokens integration_tokens_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_tokens
    ADD CONSTRAINT integration_tokens_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: integration_tokens integration_tokens_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_tokens
    ADD CONSTRAINT integration_tokens_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: integration_tokens integration_tokens_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_tokens
    ADD CONSTRAINT integration_tokens_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: invitations invitations_accepted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_accepted_by_fkey FOREIGN KEY (accepted_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: invitations invitations_invited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: invitations invitations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: link_click_daily link_click_daily_tracked_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.link_click_daily
    ADD CONSTRAINT link_click_daily_tracked_link_id_fkey FOREIGN KEY (tracked_link_id) REFERENCES public.tracked_links(id) ON DELETE CASCADE;


--
-- Name: link_clicks link_clicks_tracked_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.link_clicks
    ADD CONSTRAINT link_clicks_tracked_link_id_fkey FOREIGN KEY (tracked_link_id) REFERENCES public.tracked_links(id) ON DELETE CASCADE;


--
-- Name: media_assets media_assets_protection_declared_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_protection_declared_by_fkey FOREIGN KEY (protection_declared_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: media_assets media_assets_source_asset_id_workspace_id_source_protectio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_source_asset_id_workspace_id_source_protectio_fkey FOREIGN KEY (source_asset_id, workspace_id, source_protection_declared) REFERENCES public.media_assets(id, workspace_id, protection_declared);


--
-- Name: media_assets media_assets_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: media_assets media_assets_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: media_chunks media_chunks_media_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_chunks
    ADD CONSTRAINT media_chunks_media_asset_id_fkey FOREIGN KEY (media_asset_id) REFERENCES public.media_assets(id) ON DELETE CASCADE;


--
-- Name: memberships memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: memberships memberships_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: oauth_states oauth_states_plugin_app_registration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_states
    ADD CONSTRAINT oauth_states_plugin_app_registration_id_fkey FOREIGN KEY (plugin_app_registration_id) REFERENCES public.plugin_app_registrations(id);


--
-- Name: oauth_states oauth_states_reauthorize_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_states
    ADD CONSTRAINT oauth_states_reauthorize_social_account_id_workspace_id_fkey FOREIGN KEY (reauthorize_social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id) ON DELETE CASCADE;


--
-- Name: oauth_states oauth_states_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_states
    ADD CONSTRAINT oauth_states_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;


--
-- Name: oauth_states oauth_states_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_states
    ADD CONSTRAINT oauth_states_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: oauth_states oauth_states_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_states
    ADD CONSTRAINT oauth_states_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: plugin_app_registrations plugin_app_registrations_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_app_registrations
    ADD CONSTRAINT plugin_app_registrations_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: plugin_checkpoints plugin_checkpoints_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_checkpoints
    ADD CONSTRAINT plugin_checkpoints_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: plugin_checkpoints plugin_checkpoints_publish_attempt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_checkpoints
    ADD CONSTRAINT plugin_checkpoints_publish_attempt_id_fkey FOREIGN KEY (publish_attempt_id) REFERENCES public.publish_attempts(id) ON DELETE CASCADE;


--
-- Name: plugin_checkpoints plugin_checkpoints_remote_media_handle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_checkpoints
    ADD CONSTRAINT plugin_checkpoints_remote_media_handle_id_fkey FOREIGN KEY (remote_media_handle_id) REFERENCES public.remote_media_handles(id) ON DELETE CASCADE;


--
-- Name: plugin_records plugin_records_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_records
    ADD CONSTRAINT plugin_records_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: plugin_records plugin_records_social_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_records
    ADD CONSTRAINT plugin_records_social_account_id_fkey FOREIGN KEY (social_account_id) REFERENCES public.social_accounts(id) ON DELETE CASCADE;


--
-- Name: post_media post_media_media_asset_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_media
    ADD CONSTRAINT post_media_media_asset_id_workspace_id_fkey FOREIGN KEY (media_asset_id, workspace_id) REFERENCES public.media_assets(id, workspace_id);


--
-- Name: post_media post_media_post_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_media
    ADD CONSTRAINT post_media_post_id_workspace_id_fkey FOREIGN KEY (post_id, workspace_id) REFERENCES public.posts(id, workspace_id) ON DELETE CASCADE;


--
-- Name: post_metric_polls post_metric_polls_post_target_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_metric_polls
    ADD CONSTRAINT post_metric_polls_post_target_id_fkey FOREIGN KEY (post_target_id) REFERENCES public.post_targets(id) ON DELETE CASCADE;


--
-- Name: post_metric_snapshots post_metric_snapshots_post_target_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_metric_snapshots
    ADD CONSTRAINT post_metric_snapshots_post_target_id_fkey FOREIGN KEY (post_target_id) REFERENCES public.post_targets(id) ON DELETE CASCADE;


--
-- Name: post_target_media post_target_media_media_asset_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_target_media
    ADD CONSTRAINT post_target_media_media_asset_id_workspace_id_fkey FOREIGN KEY (media_asset_id, workspace_id) REFERENCES public.media_assets(id, workspace_id);


--
-- Name: post_target_media post_target_media_post_target_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_target_media
    ADD CONSTRAINT post_target_media_post_target_id_workspace_id_fkey FOREIGN KEY (post_target_id, workspace_id) REFERENCES public.post_targets(id, workspace_id) ON DELETE CASCADE;


--
-- Name: post_targets post_targets_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: post_targets post_targets_post_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_post_id_workspace_id_fkey FOREIGN KEY (post_id, workspace_id) REFERENCES public.posts(id, workspace_id);


--
-- Name: post_targets post_targets_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_social_account_id_workspace_id_fkey FOREIGN KEY (social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id);


--
-- Name: post_targets post_targets_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_targets
    ADD CONSTRAINT post_targets_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: posts posts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: posts posts_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: posts posts_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: processing_requests processing_requests_result_asset_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_requests
    ADD CONSTRAINT processing_requests_result_asset_id_workspace_id_fkey FOREIGN KEY (result_asset_id, workspace_id) REFERENCES public.media_assets(id, workspace_id);


--
-- Name: processing_requests processing_requests_source_asset_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_requests
    ADD CONSTRAINT processing_requests_source_asset_id_workspace_id_fkey FOREIGN KEY (source_asset_id, workspace_id) REFERENCES public.media_assets(id, workspace_id);


--
-- Name: provider_throttles provider_throttles_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_throttles
    ADD CONSTRAINT provider_throttles_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: provider_usage provider_usage_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_usage
    ADD CONSTRAINT provider_usage_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: publish_attempt_media publish_attempt_media_media_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempt_media
    ADD CONSTRAINT publish_attempt_media_media_asset_id_fkey FOREIGN KEY (media_asset_id) REFERENCES public.media_assets(id);


--
-- Name: publish_attempt_media publish_attempt_media_publish_attempt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempt_media
    ADD CONSTRAINT publish_attempt_media_publish_attempt_id_fkey FOREIGN KEY (publish_attempt_id) REFERENCES public.publish_attempts(id) ON DELETE CASCADE;


--
-- Name: publish_attempts publish_attempts_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempts
    ADD CONSTRAINT publish_attempts_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: publish_attempts publish_attempts_post_target_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempts
    ADD CONSTRAINT publish_attempts_post_target_id_fkey FOREIGN KEY (post_target_id) REFERENCES public.post_targets(id);


--
-- Name: publish_attempts publish_attempts_publish_intent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_attempts
    ADD CONSTRAINT publish_attempts_publish_intent_id_fkey FOREIGN KEY (publish_intent_id) REFERENCES public.publish_intents(id);


--
-- Name: publish_intents publish_intents_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_intents
    ADD CONSTRAINT publish_intents_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: publish_intents publish_intents_post_target_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publish_intents
    ADD CONSTRAINT publish_intents_post_target_id_fkey FOREIGN KEY (post_target_id) REFERENCES public.post_targets(id);


--
-- Name: queue_entries queue_entries_channel_queue_id_social_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_entries
    ADD CONSTRAINT queue_entries_channel_queue_id_social_account_id_fkey FOREIGN KEY (channel_queue_id, social_account_id) REFERENCES public.channel_queues(id, social_account_id) ON DELETE CASCADE;


--
-- Name: queue_entries queue_entries_post_target_id_social_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_entries
    ADD CONSTRAINT queue_entries_post_target_id_social_account_id_fkey FOREIGN KEY (post_target_id, social_account_id) REFERENCES public.post_targets(id, social_account_id) ON DELETE CASCADE;


--
-- Name: queue_entries queue_entries_queue_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_entries
    ADD CONSTRAINT queue_entries_queue_slot_id_fkey FOREIGN KEY (queue_slot_id) REFERENCES public.queue_slots(id) ON DELETE SET NULL;


--
-- Name: queue_slots queue_slots_channel_queue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_slots
    ADD CONSTRAINT queue_slots_channel_queue_id_fkey FOREIGN KEY (channel_queue_id) REFERENCES public.channel_queues(id) ON DELETE CASCADE;


--
-- Name: relay_deliveries relay_deliveries_publish_attempt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_deliveries
    ADD CONSTRAINT relay_deliveries_publish_attempt_id_fkey FOREIGN KEY (publish_attempt_id) REFERENCES public.publish_attempts(id);


--
-- Name: relay_deliveries relay_deliveries_social_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_deliveries
    ADD CONSTRAINT relay_deliveries_social_account_id_fkey FOREIGN KEY (social_account_id) REFERENCES public.social_accounts(id);


--
-- Name: relay_media_grants relay_media_grants_media_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_media_grants
    ADD CONSTRAINT relay_media_grants_media_asset_id_fkey FOREIGN KEY (media_asset_id) REFERENCES public.media_assets(id);


--
-- Name: relay_media_grants relay_media_grants_relay_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relay_media_grants
    ADD CONSTRAINT relay_media_grants_relay_delivery_id_fkey FOREIGN KEY (relay_delivery_id) REFERENCES public.relay_deliveries(id) ON DELETE CASCADE;


--
-- Name: remote_media_handles remote_media_handles_media_asset_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote_media_handles
    ADD CONSTRAINT remote_media_handles_media_asset_id_workspace_id_fkey FOREIGN KEY (media_asset_id, workspace_id) REFERENCES public.media_assets(id, workspace_id);


--
-- Name: remote_media_handles remote_media_handles_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote_media_handles
    ADD CONSTRAINT remote_media_handles_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: remote_media_handles remote_media_handles_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.remote_media_handles
    ADD CONSTRAINT remote_media_handles_social_account_id_workspace_id_fkey FOREIGN KEY (social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: signed_media_urls signed_media_urls_media_asset_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signed_media_urls
    ADD CONSTRAINT signed_media_urls_media_asset_id_workspace_id_fkey FOREIGN KEY (media_asset_id, workspace_id) REFERENCES public.media_assets(id, workspace_id);


--
-- Name: signed_media_urls signed_media_urls_publish_attempt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signed_media_urls
    ADD CONSTRAINT signed_media_urls_publish_attempt_id_fkey FOREIGN KEY (publish_attempt_id) REFERENCES public.publish_attempts(id) ON DELETE SET NULL;


--
-- Name: social_accounts social_accounts_connected_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_connected_by_fkey FOREIGN KEY (connected_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: social_accounts social_accounts_plugin_app_registration_id_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_plugin_app_registration_id_plugin_id_fkey FOREIGN KEY (plugin_app_registration_id, plugin_id) REFERENCES public.plugin_app_registrations(id, plugin_id);


--
-- Name: social_accounts social_accounts_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: social_accounts social_accounts_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: store_accounts store_accounts_connected_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_accounts
    ADD CONSTRAINT store_accounts_connected_by_fkey FOREIGN KEY (connected_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: store_accounts store_accounts_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_accounts
    ADD CONSTRAINT store_accounts_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: store_accounts store_accounts_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_accounts
    ADD CONSTRAINT store_accounts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: store_order_items store_order_items_store_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_order_items
    ADD CONSTRAINT store_order_items_store_order_id_fkey FOREIGN KEY (store_order_id) REFERENCES public.store_orders(id) ON DELETE CASCADE;


--
-- Name: store_order_items store_order_items_store_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_order_items
    ADD CONSTRAINT store_order_items_store_product_id_fkey FOREIGN KEY (store_product_id) REFERENCES public.store_products(id);


--
-- Name: store_orders store_orders_store_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_orders
    ADD CONSTRAINT store_orders_store_account_id_workspace_id_fkey FOREIGN KEY (store_account_id, workspace_id) REFERENCES public.store_accounts(id, workspace_id);


--
-- Name: store_product_stats store_product_stats_store_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_product_stats
    ADD CONSTRAINT store_product_stats_store_product_id_fkey FOREIGN KEY (store_product_id) REFERENCES public.store_products(id) ON DELETE CASCADE;


--
-- Name: store_products store_products_store_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_products
    ADD CONSTRAINT store_products_store_account_id_workspace_id_fkey FOREIGN KEY (store_account_id, workspace_id) REFERENCES public.store_accounts(id, workspace_id);


--
-- Name: tracked_links tracked_links_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_links
    ADD CONSTRAINT tracked_links_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: tracked_links tracked_links_post_target_id_social_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_links
    ADD CONSTRAINT tracked_links_post_target_id_social_account_id_fkey FOREIGN KEY (post_target_id, social_account_id) REFERENCES public.post_targets(id, social_account_id);


--
-- Name: tracked_links tracked_links_social_account_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_links
    ADD CONSTRAINT tracked_links_social_account_id_workspace_id_fkey FOREIGN KEY (social_account_id, workspace_id) REFERENCES public.social_accounts(id, workspace_id);


--
-- Name: tracked_links tracked_links_store_product_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_links
    ADD CONSTRAINT tracked_links_store_product_id_workspace_id_fkey FOREIGN KEY (store_product_id, workspace_id) REFERENCES public.store_products(id, workspace_id);


--
-- Name: upload_sessions upload_sessions_media_asset_id_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_sessions
    ADD CONSTRAINT upload_sessions_media_asset_id_workspace_id_fkey FOREIGN KEY (media_asset_id, workspace_id) REFERENCES public.media_assets(id, workspace_id) ON DELETE CASCADE;


--
-- Name: upload_sessions upload_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_sessions
    ADD CONSTRAINT upload_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: webhook_endpoints webhook_endpoints_plugin_app_registration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_plugin_app_registration_id_fkey FOREIGN KEY (plugin_app_registration_id) REFERENCES public.plugin_app_registrations(id);


--
-- Name: webhook_endpoints webhook_endpoints_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: webhook_endpoints webhook_endpoints_social_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_social_account_id_fkey FOREIGN KEY (social_account_id) REFERENCES public.social_accounts(id) ON DELETE CASCADE;


--
-- Name: webhook_endpoints webhook_endpoints_store_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_store_account_id_fkey FOREIGN KEY (store_account_id) REFERENCES public.store_accounts(id) ON DELETE CASCADE;


--
-- Name: webhook_events webhook_events_plugin_app_registration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_plugin_app_registration_id_fkey FOREIGN KEY (plugin_app_registration_id) REFERENCES public.plugin_app_registrations(id);


--
-- Name: webhook_events webhook_events_store_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_store_account_id_fkey FOREIGN KEY (store_account_id) REFERENCES public.store_accounts(id) ON DELETE CASCADE;


--
-- Name: webhook_events webhook_events_webhook_endpoint_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_webhook_endpoint_id_fkey FOREIGN KEY (webhook_endpoint_id) REFERENCES public.webhook_endpoints(id) ON DELETE CASCADE;


--
-- Name: workspace_plugins workspace_plugins_enabled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_plugins
    ADD CONSTRAINT workspace_plugins_enabled_by_fkey FOREIGN KEY (enabled_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: workspace_plugins workspace_plugins_plugin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_plugins
    ADD CONSTRAINT workspace_plugins_plugin_id_fkey FOREIGN KEY (plugin_id) REFERENCES public.plugins(plugin_id);


--
-- Name: workspace_plugins workspace_plugins_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_plugins
    ADD CONSTRAINT workspace_plugins_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261022000002'),
('20261022000001');

