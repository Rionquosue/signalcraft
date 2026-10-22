# frozen_string_literal: true

# Owns the idempotency key for one decision to publish a target revision
# (design specifications/08, Delivery).
class PublishIntent < ApplicationRecord
  belongs_to :post_target
  belongs_to :created_by, class_name: "User", optional: true
  has_many :publish_attempts, dependent: :restrict_with_error

  string_enum :kind, %w[scheduled publish_now manual_retry]
  string_enum :state, %w[open closed], prefix: true

  attribute :idempotency_key, :string, default: -> { SecureRandom.hex(16) }

  def close!
    update!(state: "closed", closed_at: Time.current)
  end
end
