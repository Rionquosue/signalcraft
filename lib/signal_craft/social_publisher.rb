# frozen_string_literal: true

module SignalCraft
  # Types shared between the host and social addons for publishing
  # (design specifications/04, Social addon DTO definitions and Normalized
  # errors and retry policy). Addons return these from `publish` and
  # `reconcile`, or raise one of the errors below.
  module SocialPublisher
    DELIVERY_STATES = %w[not_submitted submitted unknown].freeze
    PUBLISH_STATUSES = %w[published pending unknown].freeze
    RECONCILE_STATUSES = %w[published pending definitively_not_published unknown].freeze

    # What the host sends. Built by the host from a claimed target; frozen.
    TargetSnapshot = Struct.new(
      :target_id, :revision, :workspace_id, :social_account_id, :text, :media, :provider_options,
      :content_hash, keyword_init: true
    )

    # `checkpoint` is addon JSON (Hash) to persist for resuming; nil if none.
    PublishReceipt = Struct.new(
      :attempt_id, :submission_started_at, :remote_request_id, :remote_post_id, :checkpoint,
      :idempotency_key, keyword_init: true
    )

    PublishResult = Struct.new(:status, :receipt, :next_poll_at, :published_at, :remote_post_id, :remote_url,
                               keyword_init: true) do
      def self.published(remote_post_id: nil, remote_url: nil, published_at: nil, receipt: nil)
        new(status: "published", remote_post_id: remote_post_id, remote_url: remote_url,
            published_at: published_at, receipt: receipt)
      end

      def self.pending(next_poll_at:, receipt: nil)
        new(status: "pending", next_poll_at: next_poll_at, receipt: receipt)
      end

      def self.unknown(receipt: nil)
        new(status: "unknown", receipt: receipt)
      end
    end

    ReconcileResult = Struct.new(:status, :receipt, :next_poll_at, :published_at, :remote_post_id, :remote_url,
                                 keyword_init: true)

    # Base for every normalized addon error. `safe_message` may be shown to
    # users; it never contains credentials or raw provider bodies.
    class Error < StandardError
      attr_reader :safe_message, :provider_code, :retry_at, :delivery_state

      def initialize(safe_message = nil, provider_code: nil, retry_at: nil, delivery_state: "unknown")
        @safe_message = safe_message
        @provider_code = provider_code
        @retry_at = retry_at
        @delivery_state = DELIVERY_STATES.include?(delivery_state.to_s) ? delivery_state.to_s : "unknown"
        super(safe_message || self.class.name.split("::").last)
      end

      def error_class
        self.class.name.split("::").last
      end
    end

    class ValidationError < Error
      def initialize(safe_message = nil, **options)
        super(safe_message, delivery_state: "not_submitted", **options)
      end
    end

    class AuthenticationExpired < Error; end
    class ReauthorizationRequired < Error; end
    class PermanentFailure < Error; end
    class UnsupportedCapability < Error; end
    class UnsupportedCheckpointVersion < Error; end

    class RateLimited < Error
      SCOPES = %w[account provider provider_app].freeze
      attr_reader :scope

      def initialize(safe_message = nil, scope: "account", **options)
        @scope = SCOPES.include?(scope.to_s) ? scope.to_s : "account"
        super(safe_message, **options)
      end
    end

    # Retry only when delivery_state is "not_submitted".
    class TransientFailure < Error; end

    # The request may have reached the provider. Never resend; reconcile.
    class UnknownOutcome < Error
      attr_reader :receipt

      def initialize(safe_message = nil, receipt: nil, **options)
        @receipt = receipt
        super(safe_message, **options)
      end
    end
  end
end
