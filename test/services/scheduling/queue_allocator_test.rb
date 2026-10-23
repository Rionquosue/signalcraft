# frozen_string_literal: true

require "test_helper"

# Slot assignment, reorder and removal (design specifications/02, Scheduling
# semantics; 08, Reorder a queue).
class QueueAllocatorTest < ActiveSupport::TestCase
  # Friday 23 October 2026, 08:00 in Toronto.
  NOW = Time.utc(2026, 10, 23, 12, 0)

  setup do
    travel_to NOW
    @queue = channel_queues(:studio_bluesky)
    daily_slots!(@queue, "09:00")
  end

  test "queued targets take the next free occurrences in rank order" do
    first, second, third = 3.times.map { queued_target }

    assert_equal Time.utc(2026, 10, 23, 13, 0), first.due_at
    assert_equal Time.utc(2026, 10, 24, 13, 0), second.due_at
    assert_equal Time.utc(2026, 10, 25, 13, 0), third.due_at
    assert_equal [0, 1, 2], [first, second, third].map { |t| t.queue_entry.rank }
    assert_equal third.due_at, third.queue_entry.slot_occurrence_at
  end

  test "the plan previews a reorder without changing anything" do
    first, second = 2.times.map { queued_target }
    order = @queue.order_after_move(second.queue_entry.id, "up")

    changes = @queue.allocator.plan(order: order)

    assert_equal [second.id, first.id], changes.map { |c| c.entry.post_target_id }
    assert_equal [Time.utc(2026, 10, 24, 13, 0), Time.utc(2026, 10, 23, 13, 0)], changes.map(&:from)
    assert_equal Time.utc(2026, 10, 23, 13, 0), first.reload.due_at
  end

  test "reorder swaps occurrences atomically and bumps the version" do
    first, second = 2.times.map { queued_target }
    version = @queue.reload.version

    @queue.reorder!(@queue.order_after_move(second.queue_entry.id, "up"), expected_version: version, by: users(:bob))

    assert_equal Time.utc(2026, 10, 23, 13, 0), second.reload.due_at
    assert_equal Time.utc(2026, 10, 24, 13, 0), first.reload.due_at
    assert_equal version + 1, @queue.reload.version
    assert OutboxEvent.exists?(event_type: "queue.reordered", subject_id: @queue.id)
  end

  test "a reorder against an old version is refused" do
    first, second = 2.times.map { queued_target }
    stale = @queue.reload.version
    queued_target # someone else changed the queue

    assert_raises(Scheduling::QueueAllocator::StaleQueue) do
      @queue.reorder!([second.queue_entry.id, first.queue_entry.id], expected_version: stale, by: users(:bob))
    end
    assert_equal Time.utc(2026, 10, 23, 13, 0), first.reload.due_at
  end

  test "an order that does not match the waiting entries is refused" do
    first, = 2.times.map { queued_target }
    assert_raises(Scheduling::QueueAllocator::StaleQueue) do
      @queue.reorder!([first.queue_entry.id], expected_version: @queue.reload.version, by: users(:bob))
    end
  end

  test "removing a target moves later entries up" do
    first, second = 2.times.map { queued_target }

    first.unschedule!(by: users(:bob))

    assert_nil first.reload.queue_entry
    assert_equal Time.utc(2026, 10, 23, 13, 0), second.reload.due_at
  end

  test "entries whose time has passed keep their occurrence" do
    first, second = 2.times.map { queued_target }
    travel_to Time.utc(2026, 10, 23, 13, 5) # first is late but inside the grace window

    queued_target
    @queue.allocator.apply!

    assert_equal Time.utc(2026, 10, 23, 13, 0), first.reload.due_at
    assert_equal Time.utc(2026, 10, 24, 13, 0), second.reload.due_at
  end

  test "changing slots moves waiting entries onto the new times" do
    first, second = 2.times.map { queued_target }

    daily_slots!(@queue, "18:00")

    assert_equal Time.utc(2026, 10, 23, 22, 0), first.reload.due_at
    assert_equal Time.utc(2026, 10, 24, 22, 0), second.reload.due_at
  end

  test "a queue without slots keeps targets scheduled and waiting" do
    @queue.replace_slots!([], timezone: @queue.timezone, by: users(:alice))
    target = queued_target

    assert target.scheduled?
    assert_nil target.due_at
    assert_nil target.queue_entry.slot_occurrence_at
  end

  test "no two entries can claim one occurrence, even when written directly" do
    first, second = 2.times.map { queued_target }
    # The constraint is deferred to commit; tests never commit, so check now.
    QueueEntry.connection.execute("SET CONSTRAINTS queue_entries_slot_occurrence_key IMMEDIATE")
    assert_raises(ActiveRecord::RecordNotUnique) do
      second.queue_entry.update_columns(slot_occurrence_at: first.queue_entry.slot_occurrence_at)
    end
  end
end
