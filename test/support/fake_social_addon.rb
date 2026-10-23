# frozen_string_literal: true

# A stand-in social addon for publishing tests. Tests script its behaviour
# per call; it records every call so tests can prove nothing was resent.
class FakeSocialAddon
  SP = SignalCraft::SocialPublisher

  class << self
    attr_accessor :publish_behaviour, :reconcile_behaviour
    attr_reader :calls

    def reset!
      @calls = []
      @publish_behaviour = ->(**) { SP::PublishResult.published(remote_post_id: "remote-1", remote_url: "https://example.test/p/1") }
      @reconcile_behaviour = nil
    end
  end
  reset!

  def publish(context:, target:, media_handles:, idempotency_key:, checkpoint:)
    FakeSocialAddon.calls << [:publish, { target: target, idempotency_key: idempotency_key, context: context }]
    FakeSocialAddon.publish_behaviour.call(target: target, idempotency_key: idempotency_key, context: context)
  end

  def reconcile(context:, receipt:)
    FakeSocialAddon.calls << [:reconcile, { receipt: receipt }]
    FakeSocialAddon.reconcile_behaviour.call(receipt: receipt)
  end
end

# The same addon without reconciliation support.
class FakeSocialAddonWithoutReconcile < FakeSocialAddon
  undef_method :reconcile
end
