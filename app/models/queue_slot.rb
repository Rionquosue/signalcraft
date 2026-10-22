# frozen_string_literal: true

class QueueSlot < ApplicationRecord
  belongs_to :channel_queue

  validates :iso_weekday, inclusion: { in: 1..7 }
  validates :local_time, presence: true, uniqueness: { scope: %i[channel_queue_id iso_weekday] }
end
