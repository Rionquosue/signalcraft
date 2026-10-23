# frozen_string_literal: true

require "test_helper"

# Grace window and missed schedules (design specifications/02, Lateness and
# missed schedules). The default grace window is 900 seconds.
class LatenessTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 23, 12, 0) # Friday 08:00 in Toronto

  setup do
    travel_to NOW
    @queue = channel_queues(:studio_bluesky)
    daily_slots!(@queue, "09:00")
  end

  def manual_target(at)
    target = new_target
    target.update!(mode: "manual", state: "scheduled", due_at: at)
    target
  end

  test "a target late by less than the grace window is left to publish" do
    target = manual_target(NOW + 1.hour)
    travel_to NOW + 1.hour + 10.minutes

    Scheduling::Lateness.apply!

    assert target.reload.scheduled?
  end

  test "a fixed-time target beyond the window needs attention as schedule_missed" do
    target = manual_target(NOW + 1.hour)
    travel_to NOW + 1.hour + 16.minutes

    result = Scheduling::Lateness.apply!

    assert_equal [target.id], result.missed
    assert target.reload.needs_attention?
    assert target.attention_schedule_missed?
    assert AuditEvent.exists?(action: "post_target.schedule_missed", subject_id: target.id)
  end

  test "a queued target beyond the window moves to the next slot; later entries follow" do
    first, second = 2.times.map { queued_target }
    travel_to Time.utc(2026, 10, 23, 13, 20) # 20 minutes after first's slot

    result = Scheduling::Lateness.apply!

    assert_equal [first.id], result.moved
    assert_equal Time.utc(2026, 10, 24, 13, 0), first.reload.due_at
    assert_equal Time.utc(2026, 10, 25, 13, 0), second.reload.due_at
    assert first.scheduled?
    assert_equal first.due_at, first.queue_entry.slot_occurrence_at
  end

  test "paused accounts are left alone until resumed" do
    target = manual_target(NOW + 1.hour)
    @queue.pause!(by: users(:alice))
    travel_to NOW + 3.hours

    Scheduling::Lateness.apply!
    assert target.reload.scheduled?

    @queue.reload.resume!(by: users(:alice))
    assert target.reload.attention_schedule_missed?
  end

  test "the resume preview lists moves and missed fixed-time targets without changing them" do
    queued = queued_target
    fixed = manual_target(NOW + 2.hours)
    @queue.pause!(by: users(:alice))
    travel_to NOW + 1.day + 3.hours

    preview = @queue.reload.resume_preview

    assert_equal [queued.id], preview.moves.map { |change| change.entry.post_target_id }
    assert_equal [fixed.id], preview.missed.map(&:id)
    assert queued.reload.scheduled?
    assert_equal Time.utc(2026, 10, 23, 13, 0), queued.due_at
  end

  test "claimed targets are never treated as missed" do
    target = manual_target(NOW + 1.hour)
    target.update_columns(claim_owner: "worker", claim_expires_at: NOW + 2.hours)
    travel_to NOW + 1.hour + 30.minutes

    Scheduling::Lateness.apply!

    assert target.reload.scheduled?
  end

  test "slots can be removed while a past entry still references them" do
    target = queued_target
    travel_to Time.utc(2026, 10, 23, 13, 5) # inside the grace window; the entry keeps its slot

    daily_slots!(@queue, "18:00")

    entry = target.reload.queue_entry
    assert_nil entry.queue_slot_id
    assert_equal Time.utc(2026, 10, 23, 13, 0), entry.slot_occurrence_at
  end
end
