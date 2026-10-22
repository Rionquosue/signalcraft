# frozen_string_literal: true

class QueueEntry < ApplicationRecord
  belongs_to :channel_queue
  belongs_to :social_account
  belongs_to :post_target
  belongs_to :queue_slot, optional: true

  validates :rank, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
