# frozen_string_literal: true

module Publishing
  # Asks the addon what happened to a submitted attempt: after a pending
  # result, an unknown outcome or a stale publishing lease (design
  # specifications/04, Result mapping to target state). It never resends.
  class Reconciler
    SP = SignalCraft::SocialPublisher

    def initialize(attempt, token, now: Time.current)
      @attempt = attempt
      @token = token
      @now = now
    end

    def run
      target = @attempt.post_target.reload
      return :stale unless target.fencing_token == @token && target.awaiting_provider?

      publisher = Addons.publisher_for(@attempt.plugin)
      unless publisher.respond_to?(:reconcile)
        Results.needs_attention!(@attempt, @token, "publication_unconfirmed", now: @now)
        return :needs_attention
      end

      record(call(publisher))
    rescue Results::Superseded => e
      Rails.logger.warn("[publishing] #{e.message}")
      :superseded
    end

    private

    def call(publisher)
      publisher.reconcile(context: Context.new(@attempt), receipt: receipt)
    rescue StandardError => e
      e
    end

    def receipt
      stored = @attempt.receipt.present? ? JSON.parse(@attempt.receipt) : {}
      fields = SP::PublishReceipt.members.map(&:to_s)
      SP::PublishReceipt.new(
        attempt_id: @attempt.id, submission_started_at: @attempt.submission_started_at,
        idempotency_key: @attempt.publish_intent.idempotency_key,
        **stored.slice(*fields).transform_keys(&:to_sym).except(:attempt_id, :idempotency_key)
      )
    end

    def record(outcome)
      case outcome
      when SP::ReconcileResult
        case outcome.status
        when "published"
          Results.published!(@attempt, @token, remote_post_id: outcome.remote_post_id, remote_url: outcome.remote_url,
                                               published_at: outcome.published_at, receipt: outcome.receipt, now: @now)
          :published
        when "pending"
          Results.pending!(@attempt, @token, next_poll_at: outcome.next_poll_at, receipt: outcome.receipt, now: @now)
          :pending
        when "definitively_not_published"
          Results.retry_or_fail!(@attempt, @token, attempt_state: "not_published", now: @now)
          :retry
        else
          unconfirmed
        end
      when SP::RateLimited, SP::TransientFailure
        # Could not ask right now; ask again later. The attempt keeps its
        # state, and the pending timeout still applies.
        Results.fenced!(@attempt.post_target_id, @token, @now, state: "awaiting_provider",
                                                               next_poll_at: outcome.retry_at || @now + Results::POLL_DEFAULT)
        :pending
      when SP::UnsupportedCheckpointVersion
        Results.needs_attention!(@attempt, @token, "unsupported_checkpoint_version", error: outcome, now: @now)
        :needs_attention
      else
        unconfirmed(outcome.is_a?(Exception) ? outcome : nil)
      end
    end

    def unconfirmed(error = nil)
      @attempt.update!(state: "unknown", delivery_state: "unknown")
      Results.needs_attention!(@attempt, @token, "publication_unconfirmed", error: error, now: @now)
      :needs_attention
    end
  end
end
