# frozen_string_literal: true

module Publishing
  # Claims due targets for publishing (design specifications/08, Key
  # transactions: Claim a due target; 02, Publishing state and delivery).
  #
  # In one short transaction per target: share-lock the account's queue row
  # (so a concurrent pause or reallocation is seen, and in the same lock
  # order those use), lock the target with SKIP LOCKED, recheck it, increment
  # its fencing token, take a lease, open or reuse the publish intent, and
  # record the attempt with its immutable snapshot. Nothing talks to a
  # provider until this has committed.
  class Claimer
    LEASE = 15.minutes

    attr_reader :owner, :now

    def initialize(owner:, now: Time.current)
      @owner = owner
      @now = now
    end

    def due_target_ids(limit: 100)
      scheduled = PostTarget.where(state: "scheduled").where("due_at <= ?", now)
      retrying = PostTarget.where(state: "retry_wait").where("retry_at <= ?", now)
      scheduled.or(retrying).where(claim_owner: nil).order(Arel.sql("coalesce(retry_at, due_at)"))
               .limit(limit).pluck(:id)
    end

    # Claims every due target it can; returns the new attempts.
    def claim_due(limit: 100)
      due_target_ids(limit: limit).filter_map { |id| claim(id) }
    end

    # Returns the PublishAttempt, or nil when the target is not claimable now
    # (locked elsewhere, no longer due, account paused) or was blocked.
    def claim(target_id)
      PostTarget.transaction do
        account_id = PostTarget.where(id: target_id).pick(:social_account_id)
        next nil unless account_id

        queue = ChannelQueue.lock("FOR SHARE").find_by(social_account_id: account_id)
        next nil if queue&.paused?

        target = PostTarget.lock("FOR UPDATE SKIP LOCKED").find_by(id: target_id)
        next nil unless target && claimable?(target)

        if (reason = Readiness.blocked_reason(target))
          block!(target, reason)
          next nil
        end

        if (retry_at = ProviderThrottle.blocking_until(target.social_account, now: now))
          target.update!(state: "retry_wait", retry_at: retry_at)
          next nil
        end

        take_claim!(target)
      end
    end

    # Claims an awaiting_provider target whose poll is due, for a reconcile
    # job. Past the pending timeout it stops as publication_unconfirmed.
    # Returns [attempt, fencing_token] or nil.
    def claim_poll(target_id, pending_timeout: SignalCraft.settings.provider_pending_timeout_seconds)
      PostTarget.transaction do
        target = PostTarget.lock("FOR UPDATE SKIP LOCKED").find_by(id: target_id)
        next nil unless target&.awaiting_provider? && target.claim_owner.nil? && target.next_poll_at <= now

        attempt = target.publish_attempts.order(:fencing_token).last
        started = attempt&.submission_started_at || attempt&.started_at
        if attempt.nil? || started + pending_timeout.seconds < now
          Results.unconfirmed!(target, attempt, now: now)
          next nil
        end

        target.update!(fencing_token: target.fencing_token + 1, claim_owner: owner,
                       claim_expires_at: now + LEASE)
        [attempt, target.fencing_token]
      end
    end

    private

    def claimable?(target)
      return false unless target.claim_owner.nil?

      (target.scheduled? && target.due_at && target.due_at <= now) ||
        (target.retry_wait? && target.retry_at <= now)
    end

    def block!(target, reason)
      target.update!(state: "blocked", blocked_reason: reason, retry_at: nil)
      AuditEvent.record!(action: "post_target.blocked", actor: nil, workspace: target.workspace, subject: target,
                         details: { reason: reason })
    end

    def take_claim!(target)
      target.update!(state: "preparing", retry_at: nil, fencing_token: target.fencing_token + 1,
                     claim_owner: owner, claim_expires_at: now + LEASE)
      intent = current_intent(target)
      snapshot, content_hash = Snapshot.build(target)
      plugin = target.social_account.plugin
      intent.publish_attempts.create!(
        post_target: target, attempt_number: (intent.publish_attempts.maximum(:attempt_number) || 0) + 1,
        fencing_token: target.fencing_token, plugin_id: plugin.plugin_id, plugin_version: plugin.version,
        snapshot: snapshot, content_hash: content_hash, state: "claimed", started_at: now
      )
    end

    # Retries of one decision to publish reuse its intent and idempotency key.
    # A new revision is a new decision, so it gets a new intent (04, Normalized
    # errors and retry policy). Targets only reach a claim with an open intent
    # from retry_wait, where the provider is known not to have the post.
    def current_intent(target)
      open = target.publish_intents.state_open.first
      return open if open && open.target_revision == target.revision

      open&.close!
      user_requested = target.now? && target.updated_by
      target.publish_intents.create!(target_revision: target.revision, state: "open",
                                     kind: user_requested ? "publish_now" : "scheduled",
                                     created_by: user_requested ? target.updated_by : nil)
    end
  end
end
