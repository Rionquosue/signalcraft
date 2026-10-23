# frozen_string_literal: true

# One account's posting queue (design specifications/02, Scheduling semantics).
#
# Every operation that changes queue assignments locks this row first, then
# any target rows; claims take the same order (Publishing::Claimer), so the
# two never deadlock.
class ChannelQueue < ApplicationRecord
  belongs_to :workspace
  belongs_to :social_account
  belongs_to :pauser, class_name: "User", foreign_key: :paused_by, optional: true
  has_many :queue_slots, -> { order(:iso_weekday, :local_time) }, dependent: :destroy, inverse_of: :channel_queue
  has_many :queue_entries, dependent: :destroy

  validates :timezone, presence: true
  validate :timezone_must_exist

  # The account's queue, created on first use in the workspace's time zone.
  def self.for_account!(account)
    account.channel_queue || create!(workspace_id: account.workspace_id, social_account: account,
                                     timezone: account.workspace.default_timezone)
  rescue ActiveRecord::RecordNotUnique
    account.reload.channel_queue
  end

  def allocator(now: Time.current)
    Scheduling::QueueAllocator.new(self, now: now)
  end

  # Next slot occurrences, for the slot editor preview and column headers.
  def next_occurrences(count: 10, after: Time.current)
    Scheduling::SlotCalendar.new(timezone, queue_slots.to_a).next_occurrences(after: after, count: count)
  end

  # Entries waiting for (or holding) a future slot, in rank order.
  def waiting_entries(now: Time.current)
    allocator(now: now).movable_entries
  end

  # Adds a target at the end of the queue and gives it the next free slot.
  def enqueue!(target, now: Time.current)
    transaction do
      lock!
      unless queue_entries.exists?(post_target_id: target.id)
        rank = (queue_entries.maximum(:rank) || -1) + 1
        queue_entries.create!(social_account_id: social_account_id, post_target: target, rank: rank)
      end
      allocator(now: now).apply!
    end
  end

  # Removes a target from the queue; later entries move up.
  def dequeue!(target, now: Time.current)
    transaction do
      lock!
      entry = queue_entries.find_by(post_target_id: target.id)
      next unless entry

      entry.destroy!
      allocator(now: now).apply!
    end
  end

  # `order` lists the waiting entries' ids in their new order.
  def reorder!(order, expected_version:, by:, now: Time.current)
    transaction do
      changes = allocator(now: now).apply!(order: order, expected_version: expected_version, event: "queue.reordered")
      AuditEvent.record!(action: "queue.reordered", actor: by, workspace: workspace, subject: self,
                         details: { moved: changes.count(&:moved?) })
      changes
    end
  end

  # The order that results from moving one waiting entry up or down.
  def order_after_move(entry_id, direction, now: Time.current)
    ids = waiting_entries(now: now).map(&:id)
    index = ids.index(entry_id.to_s) or raise ActiveRecord::RecordNotFound
    swap = direction.to_s == "up" ? index - 1 : index + 1
    return ids if swap.negative? || swap >= ids.size

    ids[index], ids[swap] = ids[swap], ids[index]
    ids
  end

  # Replaces the recurring slots (`slots`: [[iso_weekday, "HH:MM"], ...]) and
  # time zone, then moves waiting entries onto the new occurrences.
  def replace_slots!(slots, timezone:, by:, expected_version: nil, now: Time.current)
    transaction do
      lock!
      raise Scheduling::QueueAllocator::StaleQueue if expected_version && version != Integer(expected_version)

      update!(timezone: timezone)
      queue_slots.delete_all
      slots.uniq.each { |weekday, time| queue_slots.create!(iso_weekday: weekday, local_time: time) }
      queue_slots.reset
      allocator(now: now).apply!(event: "queue.slots_changed")
      AuditEvent.record!(action: "queue.slots_changed", actor: by, workspace: workspace, subject: self,
                         details: { timezone: timezone, slots: slots.map { |w, t| "#{w} #{t}" } })
    end
  end

  def pause!(by:)
    transaction do
      lock!
      update!(paused: true, paused_at: Time.current, pauser: by)
      OutboxEvent.announce!("queue.paused", subject: self, workspace: workspace)
      AuditEvent.record!(action: "queue.paused", actor: by, workspace: workspace, subject: self)
    end
  end

  # Resuming applies the missed-schedule rule to everything that fell due
  # while paused: queue items move to their next slots, fixed-time items
  # need a decision (design specifications/02, Lateness and missed schedules).
  def resume!(by: nil, now: Time.current)
    transaction do
      lock!
      update!(paused: false, paused_at: nil, pauser: nil)
      OutboxEvent.announce!("queue.resumed", subject: self, workspace: workspace)
      AuditEvent.record!(action: "queue.resumed", actor: by, workspace: workspace, subject: self)
    end
    Scheduling::Lateness.apply!(now: now, accounts: [social_account_id])
  end

  # What resuming now would do, without changing anything.
  ResumePreview = Struct.new(:moves, :missed, keyword_init: true)

  def resume_preview(now: Time.current, grace: SignalCraft.settings.missed_schedule_grace_seconds)
    cutoff = now - grace.seconds
    overdue = PostTarget.where(social_account_id: social_account_id, state: "scheduled", claim_owner: nil)
                        .where("due_at < ?", cutoff)
    released = queue_entries.where(post_target_id: overdue.where(mode: "queue").select(:id)).pluck(:id)
    moves = allocator(now: now).plan(release: released).select(&:moved?)
    ResumePreview.new(moves: moves, missed: overdue.where.not(mode: "queue").includes(:post).order(:due_at).to_a)
  end

  private

  def timezone_must_exist
    errors.add(:timezone, "is not a known time zone") unless ActiveSupport::TimeZone[timezone.to_s]
  end
end
