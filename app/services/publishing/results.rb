# frozen_string_literal: true

module Publishing
  # Writes publishing outcomes (design specifications/04, Result mapping to
  # target state; 08, Record a provider result).
  #
  # Every target update is fenced: it applies only while the target still
  # carries the fencing token of the claim that produced the result. Zero
  # rows means a newer claim superseded this one, and the caller stops. The
  # attempt row is updated regardless, because it is the evidence of what
  # happened at the provider.
  module Results
    class Superseded < StandardError; end

    MAX_RETRIES = 5
    POLL_DEFAULT = 60.seconds

    module_function

    def published!(attempt, token, remote_post_id:, remote_url:, published_at:, receipt:, now: Time.current)
      attempt.update!(state: "published", delivery_state: "submitted", finished_at: now,
                      remote_post_id: remote_post_id, remote_url: remote_url, receipt: encode(receipt))
      fenced!(attempt.post_target_id, token, now, state: "published", published_at: published_at || now,
                                                remote_post_id: remote_post_id, remote_url: remote_url,
                                                next_poll_at: nil)
      attempt.publish_intent.close!
      # Published targets leave the queue for History (05).
      QueueEntry.where(post_target_id: attempt.post_target_id).delete_all
    end

    def pending!(attempt, token, next_poll_at:, receipt:, now: Time.current)
      attempt.update!(state: "pending", delivery_state: "submitted", receipt: encode(receipt) || attempt.receipt)
      fenced!(attempt.post_target_id, token, now, state: "awaiting_provider",
                                                next_poll_at: next_poll_at || now + POLL_DEFAULT)
    end

    # The outcome is not known: reconcile at once, never resend blindly.
    def unknown!(attempt, token, receipt: nil, error: nil, now: Time.current)
      attempt.update!(state: "unknown", delivery_state: "unknown", receipt: encode(receipt) || attempt.receipt,
                      **error_fields(error))
      fenced!(attempt.post_target_id, token, now, state: "awaiting_provider", next_poll_at: now)
    end

    # Known not to be published: retry under the policy, or fail.
    def retry_or_fail!(attempt, token, error: nil, retry_at: nil, attempt_state: "failed", now: Time.current)
      finish_not_submitted!(attempt, attempt_state, error, now)
      attempts = attempt.publish_intent.publish_attempts.count
      if attempts > MAX_RETRIES
        failed!(attempt, token, now: now, update_attempt: false)
      else
        fenced!(attempt.post_target_id, token, now, state: "retry_wait",
                                                  retry_at: retry_at || now + backoff(attempts), next_poll_at: nil)
      end
    end

    def failed!(attempt, token, error: nil, now: Time.current, update_attempt: true)
      finish_not_submitted!(attempt, "failed", error, now) if update_attempt
      fenced!(attempt.post_target_id, token, now, state: "failed", next_poll_at: nil)
      attempt.publish_intent.close!
    end

    def blocked!(attempt, token, reason, error: nil, now: Time.current)
      finish_not_submitted!(attempt, "failed", error, now)
      fenced!(attempt.post_target_id, token, now, state: "blocked", blocked_reason: reason, next_poll_at: nil)
      attempt.publish_intent.close!
    end

    def needs_attention!(attempt, token, reason, error: nil, now: Time.current)
      attempt.update!(finished_at: now, **error_fields(error))
      fenced!(attempt.post_target_id, token, now, state: "needs_attention", attention_reason: reason,
                                                next_poll_at: nil)
    end

    # Pending too long, or the provider cannot say: never retried blindly.
    def unconfirmed!(target, attempt, now: Time.current)
      attempt&.update!(state: "unknown", finished_at: now) unless attempt.nil? || attempt.state_published?
      target.update!(state: "needs_attention", attention_reason: "publication_unconfirmed", next_poll_at: nil,
                     claim_owner: nil, claim_expires_at: nil)
    end

    def fenced!(target_id, token, now, **attributes)
      defaults = { attention_reason: nil, blocked_reason: nil, retry_at: nil }
      rows = PostTarget.where(id: target_id, fencing_token: token)
                       .update_all(defaults.merge(attributes).merge(claim_owner: nil, claim_expires_at: nil,
                                                                    updated_at: now,
                                                                    lock_version: Arel.sql("lock_version + 1")))
      raise Superseded, "claim #{token} on target #{target_id} was superseded" if rows.zero?
    end

    def finish_not_submitted!(attempt, state, error, now)
      attempt.update!(state: state, delivery_state: "not_submitted", finished_at: now, **error_fields(error))
    end

    # Capped exponential backoff with jitter: about 30 s, 1, 2, 4, 8 min.
    def backoff(attempts)
      base = [30 * (2**(attempts - 1)), 3600].min
      (base * rand(0.8..1.2)).round.seconds
    end

    def error_fields(error)
      return {} unless error

      safe = error.respond_to?(:safe_message) ? error.safe_message : nil
      { error_class: (error.respond_to?(:error_class) ? error.error_class : error.class.name.demodulize).first(64),
        provider_code: (error.provider_code if error.respond_to?(:provider_code))&.to_s&.first(128),
        safe_message: (safe || "The addon raised an unexpected error").first(1000),
        retry_at: (error.retry_at if error.respond_to?(:retry_at)) }
    end

    def encode(receipt)
      return nil if receipt.nil?

      JSON.generate(receipt.respond_to?(:to_h) ? receipt.to_h : receipt)
    end
  end
end
