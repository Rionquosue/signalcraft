# frozen_string_literal: true

module Publishing
  # Sends one claimed attempt through its addon and records the outcome
  # (design specifications/02, Publishing state and delivery; 04, Result
  # mapping to target state and Normalized errors).
  #
  # 1. Short transaction: recheck the claim (fencing token, state), pause,
  #    revision and readiness; mark the attempt submitting. Before the call
  #    the delivery state is "unknown", so a crash mid-call is reconciled
  #    rather than resent.
  # 2. Call the addon with no database locks or transaction held.
  # 3. Record the result with fenced updates (Results).
  class Executor
    SP = SignalCraft::SocialPublisher

    attr_reader :attempt

    def initialize(attempt, now: Time.current)
      @attempt = attempt
      @now = now
    end

    # Returns a symbol describing what happened, for logs and tests.
    def run
      return :stale unless begin_submission!

      record(call_addon)
    rescue Results::Superseded => e
      Rails.logger.warn("[publishing] #{e.message}")
      :superseded
    end

    private

    def token
      attempt.fencing_token
    end

    def begin_submission!
      PostTarget.transaction do
        queue = ChannelQueue.lock("FOR SHARE").find_by(social_account_id: attempt.post_target.social_account_id)
        target = PostTarget.lock.find(attempt.post_target_id)
        attempt.reload
        next false unless target.fencing_token == token && target.claim_owner && target.preparing? &&
                          attempt.state_claimed?

        if queue&.paused? || target.revision != attempt.snapshot["revision"]
          # Not sent: give the target back to the scheduler unchanged.
          attempt.update!(state: "abandoned", finished_at: @now)
          Results.fenced!(target.id, token, @now, state: "scheduled")
          next false
        end

        if (reason = Readiness.blocked_reason(target))
          Results.blocked!(attempt, token, reason, now: @now)
          next false
        end

        attempt.update!(state: "submitting", delivery_state: "unknown", submission_started_at: @now)
        target.update!(state: "publishing")
        true
      end
    end

    def call_addon
      publisher = Addons.publisher_for(attempt.plugin)
      return SP::UnknownOutcome.new("The addon is no longer available") unless publisher

      context = Context.new(attempt)
      publisher.publish(context: context, target: Snapshot.to_dto(attempt.snapshot), media_handles: [],
                        idempotency_key: attempt.publish_intent.idempotency_key,
                        checkpoint: context.checkpoints.load)
    rescue StandardError => e
      e
    end

    def record(outcome)
      case outcome
      when SP::PublishResult then record_result(outcome)
      when SP::Error then record_error(outcome)
      else
        # An unexpected exception or return value: the request may have been
        # sent, so treat the outcome as unknown.
        Results.unknown!(attempt, token, error: outcome.is_a?(Exception) ? outcome : nil, now: @now)
        :unknown
      end
    end

    def record_result(result)
      case result.status
      when "published"
        Results.published!(attempt, token, remote_post_id: result.remote_post_id, remote_url: result.remote_url,
                                           published_at: result.published_at, receipt: result.receipt, now: @now)
        :published
      when "pending"
        Results.pending!(attempt, token, next_poll_at: result.next_poll_at, receipt: result.receipt, now: @now)
        :pending
      else
        Results.unknown!(attempt, token, receipt: result.receipt, now: @now)
        :unknown
      end
    end

    def record_error(error)
      case error
      when SP::ValidationError, SP::UnsupportedCapability
        Results.blocked!(attempt, token, "validation_failed", error: error, now: @now)
        :blocked
      when SP::ReauthorizationRequired, SP::AuthenticationExpired
        # Credential refresh under the account lease arrives with account
        # connections; until then an expired login needs reconnecting.
        if error.is_a?(SP::ReauthorizationRequired)
          attempt.post_target.social_account.update!(connection_status: "reauthorization_required")
        end
        Results.blocked!(attempt, token, "reauthorization_required", error: error, now: @now)
        :blocked
      when SP::RateLimited
        if error.retry_at
          ProviderThrottle.record!(attempt.post_target.social_account, scope: error.scope, retry_at: error.retry_at,
                                                                       now: @now)
        end
        retry_if_not_submitted(error, retry_at: error.retry_at)
      when SP::TransientFailure
        retry_if_not_submitted(error)
      when SP::PermanentFailure
        Results.failed!(attempt, token, error: error, now: @now)
        :failed
      when SP::UnsupportedCheckpointVersion
        Results.needs_attention!(attempt, token, "unsupported_checkpoint_version", error: error, now: @now)
        :needs_attention
      when SP::UnknownOutcome
        Results.unknown!(attempt, token, receipt: error.receipt, error: error, now: @now)
        :unknown
      else
        Results.unknown!(attempt, token, error: error, now: @now)
        :unknown
      end
    end

    # Retry only when the addon knows nothing reached the provider.
    def retry_if_not_submitted(error, retry_at: nil)
      if error.delivery_state == "not_submitted"
        Results.retry_or_fail!(attempt, token, error: error, retry_at: retry_at, now: @now)
        :retry
      else
        Results.unknown!(attempt, token, error: error, now: @now)
        :unknown
      end
    end
  end
end
