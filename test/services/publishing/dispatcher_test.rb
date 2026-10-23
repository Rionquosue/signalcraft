# frozen_string_literal: true

require "test_helper"

# Claims, fencing tokens and outcome recording (design specifications/02,
# Publishing state and delivery; 04, Result mapping and Normalized errors;
# 08, Key transactions).
class DispatcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SP = SignalCraft::SocialPublisher
  NOW = Time.utc(2026, 10, 23, 12, 0)

  setup do
    travel_to NOW
    use_fake_addon!
  end

  def due_target(at: NOW - 1.minute, account: social_accounts(:studio_bluesky), body: "Due post")
    target = new_target(account: account, body: body)
    target.update!(mode: "manual", state: "scheduled", due_at: at)
    target
  end

  def dispatch(now: Time.current)
    Publishing::Dispatcher.new(now: now, owner: "test-worker").run
  end

  def claim(target, now: Time.current)
    Publishing::Claimer.new(owner: "test-worker", now: now).claim(target.id)
  end

  def run_attempt(attempt, now: Time.current)
    Publishing::Executor.new(attempt.reload, now: now).run
  end

  def publish_calls
    FakeSocialAddon.calls.count { |kind, _| kind == :publish }
  end

  # --- Claims ------------------------------------------------------------------

  test "a claim fences the target, records a snapshot and opens an intent before any sending" do
    target = due_target

    attempt = claim(target)

    target.reload
    assert target.preparing?
    assert_equal 1, target.fencing_token
    assert_equal "test-worker", target.claim_owner
    assert_equal NOW + Publishing::Claimer::LEASE, target.claim_expires_at
    assert_equal target.fencing_token, attempt.fencing_token
    assert attempt.state_claimed?
    assert_equal "Due post", attempt.snapshot["text"]
    assert_equal attempt.snapshot["content_hash"], attempt.content_hash.unpack1("H*")
    assert attempt.publish_intent.state_open?
    assert_equal "scheduled", attempt.publish_intent.kind
    assert_equal 0, publish_calls
  end

  test "a claimed target cannot be claimed again" do
    target = due_target
    assert claim(target)
    assert_nil claim(target)
    assert_equal 1, target.publish_attempts.count
  end

  test "targets that are not yet due are not claimed" do
    target = due_target(at: NOW + 5.minutes)
    assert_nil claim(target)
    assert target.reload.scheduled?
  end

  test "a paused account's targets are not claimed" do
    target = due_target
    channel_queues(:studio_bluesky).pause!(by: users(:alice))

    assert_nil claim(target)
    assert target.reload.scheduled?
  end

  test "the snapshot cannot be changed after it is recorded" do
    attempt = claim(due_target)
    # Written directly, past Active Record's attr_readonly, to reach the trigger.
    assert_raises(ActiveRecord::StatementInvalid) do
      PublishAttempt.where(id: attempt.id).update_all(snapshot: attempt.snapshot.merge("text" => "Changed"))
    end
  end

  # --- Sending and results ----------------------------------------------------------

  test "a published result completes the target, closes the intent and leaves the queue" do
    daily_slots!(channel_queues(:studio_bluesky), "09:00")
    target = queued_target
    travel_to target.due_at + 1.minute

    perform_enqueued_jobs { dispatch }

    target.reload
    assert target.published?
    assert_equal "remote-1", target.remote_post_id
    assert_nil target.claim_owner
    assert_nil target.queue_entry
    attempt = target.publish_attempts.sole
    assert attempt.state_published?
    assert attempt.delivery_submitted?
    assert attempt.publish_intent.state_closed?
    assert_equal 1, publish_calls
  end

  test "the addon receives the intent's idempotency key and the frozen snapshot" do
    attempt = claim(due_target)
    run_attempt(attempt)

    _, call = FakeSocialAddon.calls.first
    assert_equal attempt.publish_intent.idempotency_key, call[:idempotency_key]
    assert call[:target].frozen?
    assert_equal "Due post", call[:target].text
  end

  test "running the same attempt twice sends once" do
    attempt = claim(due_target)

    assert_equal :published, run_attempt(attempt)
    assert_equal :stale, run_attempt(attempt)
    assert_equal 1, publish_calls
  end

  test "duplicate dispatcher passes publish once" do
    target = due_target

    perform_enqueued_jobs do
      dispatch
      dispatch
    end

    assert target.reload.published?
    assert_equal 1, publish_calls
  end

  test "a result from a superseded claim is not recorded on the target" do
    target = due_target
    attempt = claim(target)
    FakeSocialAddon.publish_behaviour = lambda do |**|
      # Another worker took over while this one was waiting on the provider.
      PostTarget.where(id: target.id).update_all("fencing_token = fencing_token + 1")
      SP::PublishResult.published(remote_post_id: "late")
    end

    assert_equal :superseded, run_attempt(attempt)
    assert target.reload.publishing?
    assert_nil target.remote_post_id
    assert attempt.reload.state_published? # the evidence is kept for reconciliation
  end

  test "a pending result waits for the provider and is polled by a new job" do
    target = due_target
    FakeSocialAddon.publish_behaviour = ->(**) { SP::PublishResult.pending(next_poll_at: NOW + 2.minutes) }
    run_attempt(claim(target))
    assert target.reload.awaiting_provider?
    assert_equal NOW + 2.minutes, target.next_poll_at

    FakeSocialAddon.reconcile_behaviour = lambda do |**|
      SP::ReconcileResult.new(status: "published", remote_post_id: "remote-9")
    end
    travel_to NOW + 3.minutes
    perform_enqueued_jobs { dispatch }

    assert target.reload.published?
    assert_equal "remote-9", target.remote_post_id
    assert_equal 1, publish_calls
  end

  test "pending past the provider timeout becomes publication_unconfirmed" do
    target = due_target
    FakeSocialAddon.publish_behaviour = ->(**) { SP::PublishResult.pending(next_poll_at: NOW + 1.minute) }
    run_attempt(claim(target))

    travel_to NOW + 2.hours
    dispatch

    assert target.reload.needs_attention?
    assert target.attention_publication_unconfirmed?
  end

  # --- Errors and retries -----------------------------------------------------------

  test "a transient failure before submission is retried with the same idempotency key" do
    target = due_target
    FakeSocialAddon.publish_behaviour = lambda do |**|
      raise SP::TransientFailure.new("Service busy", delivery_state: "not_submitted")
    end
    first = claim(target)
    assert_equal :retry, run_attempt(first)
    assert target.reload.retry_wait?
    assert target.retry_at > NOW

    FakeSocialAddon.publish_behaviour = ->(**) { SP::PublishResult.published(remote_post_id: "ok") }
    travel_to target.retry_at + 1.second
    second = claim(target)
    run_attempt(second)

    assert target.reload.published?
    assert_equal first.publish_intent_id, second.publish_intent_id
    assert_equal 2, second.attempt_number
    assert_equal "TransientFailure", first.reload.error_class
  end

  test "a transient failure that may have reached the provider is reconciled, never resent" do
    target = due_target
    FakeSocialAddon.publish_behaviour = lambda do |**|
      raise SP::TransientFailure.new("Timed out", delivery_state: "unknown")
    end
    assert_equal :unknown, run_attempt(claim(target))
    assert target.reload.awaiting_provider?

    FakeSocialAddon.reconcile_behaviour = ->(**) { SP::ReconcileResult.new(status: "unknown") }
    perform_enqueued_jobs { dispatch }

    assert target.reload.attention_publication_unconfirmed?
    assert_equal 1, publish_calls
  end

  test "retries stop after five" do
    target = due_target
    FakeSocialAddon.publish_behaviour = lambda do |**|
      raise SP::TransientFailure.new("Busy", delivery_state: "not_submitted")
    end
    6.times do
      attempt = claim(target)
      run_attempt(attempt)
      target.reload
      travel_to target.retry_at + 1.second if target.retry_wait?
    end

    assert target.reload.failed?
    assert_equal 6, publish_calls
  end

  test "a rate limit is stored at its scope and holds back the account's other targets" do
    first = due_target
    second = due_target(body: "Second")
    FakeSocialAddon.publish_behaviour = lambda do |**|
      raise SP::RateLimited.new("Daily allowance used", scope: "provider_app", retry_at: NOW + 6.hours,
                                                        delivery_state: "not_submitted")
    end
    run_attempt(claim(first))

    throttle = ProviderThrottle.sole
    assert throttle.scope_provider_app?
    assert_equal social_accounts(:studio_bluesky).plugin_app_registration_id, throttle.scope_key
    assert_equal NOW + 6.hours, first.reload.retry_at

    assert_nil claim(second)
    assert second.reload.retry_wait?
    assert_equal NOW + 6.hours, second.retry_at
  end

  test "a validation error blocks the target with its reason" do
    target = due_target
    FakeSocialAddon.publish_behaviour = ->(**) { raise SP::ValidationError, "Text is too long" }

    run_attempt(claim(target))

    assert target.reload.blocked?
    assert target.blocked_by_validation_failed?
    assert_equal "Text is too long", target.publish_attempts.sole.safe_message
  end

  test "an unexpected addon exception is treated as an unknown outcome" do
    target = due_target
    FakeSocialAddon.publish_behaviour = ->(**) { raise "socket closed" }

    assert_equal :unknown, run_attempt(claim(target))
    assert target.reload.awaiting_provider?
    assert target.publish_attempts.sole.state_unknown?
  end

  test "an unsupported checkpoint version stops the target for the owner" do
    target = due_target
    FakeSocialAddon.publish_behaviour = ->(**) { raise SP::UnsupportedCheckpointVersion, "Checkpoint v3" }

    run_attempt(claim(target))

    assert target.reload.attention_unsupported_checkpoint_version?
  end

  # --- Readiness -----------------------------------------------------------------------

  test "a disabled addon or disconnected account blocks instead of claiming" do
    disabled = due_target
    WorkspacePlugin.update_all(enabled: false)
    assert_nil claim(disabled)
    assert disabled.reload.blocked_by_plugin_disabled?

    WorkspacePlugin.update_all(enabled: true)
    disconnected = due_target(body: "Other")
    social_accounts(:studio_bluesky).update!(connection_status: "disconnected")
    assert_nil claim(disconnected)
    assert disconnected.reload.blocked_by_account_disconnected?
  end

  test "an addon whose code is missing blocks as plugin_unavailable" do
    plugins(:bluesky).update!(manifest: plugins(:bluesky).manifest.merge("entrypoint" => "NoSuchAddon"))
    target = due_target

    assert_nil claim(target)
    assert target.reload.blocked_by_plugin_unavailable?
  end

  test "pausing between claim and send gives the target back without sending" do
    target = due_target
    attempt = claim(target)
    channel_queues(:studio_bluesky).pause!(by: users(:alice))

    assert_equal :stale, run_attempt(attempt)
    assert target.reload.scheduled?
    assert attempt.reload.state_abandoned?
    assert_equal 0, publish_calls
  end

  # --- Stale leases (crash recovery) ---------------------------------------------

  test "a lease that expires before sending is retried" do
    target = due_target
    attempt = claim(target)

    travel_to NOW + Publishing::Claimer::LEASE + 1.minute
    Publishing::Dispatcher.new(owner: "other").recover_stale_claims

    target.reload
    assert target.retry_wait?
    assert_equal 2, target.fencing_token
    assert attempt.reload.state_abandoned?
    assert_equal :stale, run_attempt(attempt) # the stalled worker cannot send now
  end

  test "a crash after sending is reconciled, not resent" do
    target = due_target
    attempt = claim(target)
    FakeSocialAddon.publish_behaviour = lambda do |**|
      raise Interrupt # the worker dies mid-request
    end
    assert_raises(Interrupt) { run_attempt(attempt) }
    assert target.reload.publishing?
    assert attempt.reload.state_submitting?

    FakeSocialAddon.reconcile_behaviour = ->(**) { SP::ReconcileResult.new(status: "published", remote_post_id: "found") }
    travel_to NOW + Publishing::Claimer::LEASE + 1.minute
    perform_enqueued_jobs { dispatch }

    assert target.reload.published?
    assert_equal "found", target.remote_post_id
    assert_equal 1, publish_calls
  end

  test "without reconciliation support an uncertain send needs attention" do
    FakeSocialAddon.reset!
    plugins(:bluesky).update!(manifest: plugins(:bluesky).manifest.merge("entrypoint" => "FakeSocialAddonWithoutReconcile"))
    target = due_target
    FakeSocialAddon.publish_behaviour = ->(**) { raise SP::UnknownOutcome, "Connection reset after upload" }
    run_attempt(claim(target))

    perform_enqueued_jobs { dispatch }

    assert target.reload.attention_publication_unconfirmed?
    assert_equal 1, publish_calls
  end

  # --- The whole pass -----------------------------------------------------------------

  test "publish now is claimed from the outbox straight away" do
    target = new_target
    target.publish_now!(by: users(:bob))

    perform_enqueued_jobs { Publishing::Dispatcher.new(owner: "test-worker").drain_outbox }

    assert target.reload.published?
    assert_equal "publish_now", target.publish_intents.sole.kind
    assert_equal users(:bob).id, target.publish_intents.sole.created_by
  end

  test "one post to three accounts publishes each at its own time and a failure stays with its target" do
    registration = plugin_app_registrations(:bsky)
    accounts = %w[two three].map do |name|
      SocialAccount.create!(workspace: workspaces(:studio), plugin_id: "bluesky", plugin_app_registration: registration,
                            provider_account_id: "did:plc:#{name}", display_name: name.capitalize,
                            credentials: "{}", connection_status: "connected")
    end
    post = Post.create!(workspace: workspaces(:studio), body: "Launch", creator: users(:alice))
    targets = [social_accounts(:studio_bluesky), *accounts].each_with_index.map do |account, index|
      PostTarget.create!(workspace: post.workspace, post: post, social_account: account, mode: "manual",
                         state: "scheduled", due_at: NOW + (index * 3).hours)
    end
    FakeSocialAddon.publish_behaviour = lambda do |target:, **|
      raise SP::PermanentFailure, "Rejected" if target.social_account_id == accounts.last.id

      SP::PublishResult.published(remote_post_id: "post-#{target.social_account_id}")
    end

    [0, 3, 6].each do |hour|
      travel_to NOW + hour.hours + 1.minute
      perform_enqueued_jobs { dispatch }
    end

    states = targets.map { |t| t.reload.state }
    assert_equal %w[published published failed], states
    assert_equal 3, targets.map { |t| t.publish_attempts.sole.id }.uniq.size
    assert_not_equal targets[0].published_at, targets[1].published_at
  end

  test "the dispatcher applies the missed-schedule rule before claiming" do
    target = due_target(at: NOW - 20.minutes)

    perform_enqueued_jobs { dispatch }

    assert target.reload.attention_schedule_missed?
    assert_equal 0, publish_calls
  end

  test "a late target inside the grace window still publishes" do
    target = due_target(at: NOW - 10.minutes)

    perform_enqueued_jobs { dispatch }

    assert target.reload.published?
  end
end
