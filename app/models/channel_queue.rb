# frozen_string_literal: true

# One account's posting queue (design specifications/02, Scheduling semantics).
class ChannelQueue < ApplicationRecord
  belongs_to :workspace
  belongs_to :social_account
  belongs_to :pauser, class_name: "User", foreign_key: :paused_by, optional: true
  has_many :queue_slots, dependent: :destroy
  has_many :queue_entries, dependent: :destroy

  validates :timezone, presence: true
  validate :timezone_must_exist

  def pause!(by:)
    update!(paused: true, paused_at: Time.current, pauser: by)
  end

  def resume!
    update!(paused: false, paused_at: nil, pauser: nil)
  end

  private

  def timezone_must_exist
    errors.add(:timezone, "is not a known time zone") unless ActiveSupport::TimeZone[timezone.to_s]
  end
end
