# frozen_string_literal: true

# Durable dispatch intent written in the same transaction as the change it
# announces (design specifications/02, Publishing state and delivery).
class OutboxEvent < ApplicationRecord
  scope :pending, -> { where(dispatched_at: nil).where("available_at <= ?", Time.current).order(:available_at, :id) }

  def self.announce!(event_type, subject:, payload: {}, workspace: nil)
    create!(event_type: event_type, subject_type: subject.class.name, subject_id: subject.id,
            payload: payload, workspace_id: workspace&.id)
  end
end
