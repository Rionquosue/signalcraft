# frozen_string_literal: true

# One claim and send. The snapshot of what was sent can never change; the
# database enforces this with a trigger (design specifications/08).
class PublishAttempt < ApplicationRecord
  belongs_to :publish_intent
  belongs_to :post_target
  belongs_to :plugin, foreign_key: :plugin_id, primary_key: :plugin_id

  string_enum :state, %w[claimed submitting pending published not_published unknown failed abandoned]
  string_enum :delivery_state, %w[not_submitted submitted unknown], prefix: :delivery

  encrypts :receipt
  attr_readonly :snapshot, :content_hash, :publish_intent_id, :post_target_id, :fencing_token
end
