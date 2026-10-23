# frozen_string_literal: true

# Encrypted addon state for resuming one publish attempt or one remote media
# handle (design specifications/04, Checkpoint and state versioning).
class PluginCheckpoint < ApplicationRecord
  MAX_PLAINTEXT_BYTES = 64 * 1024

  belongs_to :plugin, foreign_key: :plugin_id, primary_key: :plugin_id
  belongs_to :publish_attempt, optional: true

  encrypts :data

  validate :data_within_limit

  def payload
    JSON.parse(data)
  end

  private

  def data_within_limit
    errors.add(:data, "is larger than 64 KiB") if data.to_s.bytesize > MAX_PLAINTEXT_BYTES
  end
end
