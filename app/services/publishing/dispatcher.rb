# frozen_string_literal: true

module Publishing
  # One dispatcher pass, run every DISPATCH_INTERVAL_SECONDS by DispatchJob
  # (design specifications/02, Lateness and missed schedules and Publishing
  # state and delivery). Every step tolerates a concurrent or duplicate pass:
  # rows are taken with SKIP LOCKED and claims are fenced.
  class Dispatcher
    Summary = Struct.new(:outbox, :moved, :missed, :recovered, :polls, :claims, keyword_init: true)

    OUTBOX_BATCH = 200

    attr_reader :now, :owner

    def initialize(now: Time.current, owner: "dispatcher:#{Socket.gethostname}:#{Process.pid}")
      @now = now
      @owner = owner
    end

    def run
      outbox = drain_outbox
      lateness = Scheduling::Lateness.apply!(now: now)
      recovered = recover_stale_claims
      polls = claim_polls
      attempts = Claimer.new(owner: owner, now: now).claim_due
      attempts.each { |attempt| PublishAttemptJob.perform_later(attempt.id) }
      ProcessHeartbeat.beat!(role: "worker")
      Summary.new(outbox: outbox, moved: lateness.moved.size, missed: lateness.missed.size, recovered: recovered,
                  polls: polls, claims: attempts.size)
    end

    # Outbox events are durable notes of changes made in the same
    # transaction. A publish request is claimed straight away; everything
    # else is picked up by the scans below, so it only needs marking.
    def drain_outbox
      count = 0
      OutboxEvent.transaction do
        OutboxEvent.where(dispatched_at: nil).where("available_at <= ?", now).order(:available_at, :id)
                   .lock("FOR UPDATE SKIP LOCKED").limit(OUTBOX_BATCH).each do |event|
          # A savepoint, so one failing handler cannot abort the batch.
          OutboxEvent.transaction(requires_new: true) { handle(event) }
          event.update!(dispatched_at: now)
          count += 1
        rescue StandardError => e
          event.update!(attempt_count: event.attempt_count + 1, last_error: e.message.first(1000),
                        available_at: now + (2**[event.attempt_count, 10].min).seconds)
        end
      end
      count
    end

    # A lease that ran out means its worker died or stalled. Bumping the
    # fencing token stops a stalled worker from recording anything later.
    # - Never submitted: safe to retry.
    # - Possibly submitted: reconcile; never resend blindly.
    def recover_stale_claims
      ids = PostTarget.where.not(claim_owner: nil).where("claim_expires_at < ?", now).pluck(:id)
      ids.count { |id| recover(id) }
    end

    def claim_polls
      claimer = Claimer.new(owner: owner, now: now)
      PostTarget.where(state: "awaiting_provider", claim_owner: nil).where("next_poll_at <= ?", now)
                .order(:next_poll_at).limit(100).pluck(:id).count do |id|
        attempt, token = claimer.claim_poll(id)
        ReconcileAttemptJob.perform_later(attempt.id, token) if attempt
        attempt
      end
    end

    private

    def handle(event)
      return unless event.event_type == "post_target.publish_requested"

      attempt = Claimer.new(owner: owner, now: now).claim(event.subject_id)
      PublishAttemptJob.perform_later(attempt.id) if attempt
    end

    def recover(id)
      PostTarget.transaction do
        target = PostTarget.lock("FOR UPDATE SKIP LOCKED").find_by(id: id)
        next false unless target&.claim_owner && target.claim_expires_at < now

        attempt = target.publish_attempts.find_by(fencing_token: target.fencing_token)
        expired_owner = target.claim_owner
        fence = { fencing_token: target.fencing_token + 1, claim_owner: nil, claim_expires_at: nil }
        if target.preparing? || attempt&.state_claimed?
          attempt&.update!(state: "abandoned", finished_at: now)
          target.update!(state: "retry_wait", retry_at: now, **fence)
        else
          attempt.update!(state: "unknown", delivery_state: "unknown") if attempt&.state_submitting?
          target.update!(state: "awaiting_provider", next_poll_at: now, **fence)
        end
        AuditEvent.record!(action: "post_target.claim_expired", actor: nil, workspace: target.workspace,
                           subject: target, details: { claim_owner: expired_owner, state: target.state })
        true
      end
    end
  end
end
