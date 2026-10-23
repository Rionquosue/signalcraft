# frozen_string_literal: true

module Scheduling
  # Assigns a queue's waiting entries to its next slot occurrences, in rank
  # order (design specifications/02, Scheduling semantics; 08, Reorder a queue).
  #
  # Only future assignments move. An entry is movable while its target is
  # scheduled, unclaimed and its occurrence is still ahead (or it has none).
  # Entries whose time has passed keep their occurrence, so the dispatcher can
  # still publish them within the grace window; Lateness releases them
  # explicitly once the window has closed.
  #
  # #plan is side-effect free and powers the "preview changed dates" step;
  # #apply! locks the queue, checks its version, and rewrites ranks,
  # occurrences and target due times in one transaction. The deferrable
  # unique constraints on (queue, rank) and (queue, slot_occurrence_at) are
  # checked at commit, so no two entries can end up claiming one occurrence.
  class QueueAllocator
    class StaleQueue < StandardError
      def initialize(msg = "This queue changed. Review the updated order.")
        super
      end
    end

    Change = Struct.new(:entry, :from, :to, :slot, keyword_init: true) do
      def moved?
        from != to
      end

      def target
        entry.post_target
      end
    end

    attr_reader :queue, :now

    def initialize(queue, now: Time.current)
      @queue = queue
      @now = now
    end

    # Entries whose occurrence may change, in rank order.
    def movable_entries(release: [])
      queue.queue_entries.joins(:post_target).includes(:post_target)
           .where(post_targets: { state: "scheduled", claim_owner: nil })
           .where("queue_entries.slot_occurrence_at IS NULL OR queue_entries.slot_occurrence_at > ? " \
                  "OR queue_entries.id IN (?)", now, release.presence || [nil])
           .order(:rank).to_a
    end

    # `order`: ids of the movable entries in their new order. `release`: ids
    # of past entries to treat as movable (missed schedules).
    def plan(order: nil, release: [])
      entries = movable_entries(release: release)
      entries = arrange(entries, order) if order
      # Occurrences still held by entries that are not moving stay theirs.
      taken = queue.queue_entries.where.not(id: entries.map(&:id)).where.not(slot_occurrence_at: nil)
                   .pluck(:slot_occurrence_at).to_set
      occurrences = SlotCalendar.new(queue.timezone, queue.queue_slots.to_a).occurrences(after: now)
                                .reject { |occurrence| taken.include?(occurrence.at) }.first(entries.size)
      entries.each_with_index.map do |entry, index|
        occurrence = occurrences[index]
        Change.new(entry: entry, from: entry.slot_occurrence_at, to: occurrence&.at, slot: occurrence&.slot)
      end
    end

    def apply!(order: nil, release: [], expected_version: nil, event: "queue.reallocated")
      ChannelQueue.transaction do
        queue.lock!
        raise StaleQueue if expected_version && queue.version != Integer(expected_version)

        changes = plan(order: order, release: release)
        rewrite_ranks(changes.map(&:entry))
        changes.select(&:moved?).each { |change| write(change) }
        queue.update!(version: queue.version + 1)
        OutboxEvent.announce!(event, subject: queue, workspace: queue.workspace,
                                     payload: { version: queue.version, moved: changes.count(&:moved?) })
        changes
      end
    end

    private

    def arrange(entries, order)
      by_id = entries.index_by(&:id)
      raise StaleQueue unless order.map(&:to_s).sort == by_id.keys.map(&:to_s).sort

      order.map { |id| by_id.fetch(id.to_s) }
    end

    # Fixed entries keep their relative order at the front; movable ones
    # follow in their new order. Ranks are rewritten densely from 0.
    def rewrite_ranks(movable)
      movable_ids = movable.map(&:id)
      fixed = queue.queue_entries.where.not(id: movable_ids).order(:rank).to_a
      (fixed + movable).each_with_index do |entry, rank|
        next if entry.rank == rank

        entry.update_columns(rank: rank, updated_at: now)
        entry.rank = rank
      end
    end

    def write(change)
      change.entry.update_columns(slot_occurrence_at: change.to, queue_slot_id: change.slot&.id, updated_at: now)
      # The target's due time always equals its entry's occurrence (08).
      PostTarget.where(id: change.entry.post_target_id).update_all(due_at: change.to, updated_at: now)
      change.target.due_at = change.to
    end
  end
end
