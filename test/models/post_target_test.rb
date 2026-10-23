# frozen_string_literal: true

require "test_helper"

# Per-platform editing (design specifications/05, Editing a queued post for one platform).
class PostTargetTest < ActiveSupport::TestCase
  setup do
    @target = post_targets(:launch_bluesky)
    @sibling = post_targets(:launch_bluesky_again)
    @editor = users(:bob)
  end

  test "editing one platform's text leaves the schedule and siblings untouched" do
    due_at = @target.due_at
    sibling_revision = @sibling.revision

    @target.edit_for_platform!(by: @editor, body: "Shorter copy for this platform")

    @target.reload
    assert_equal "Shorter copy for this platform", @target.effective_body
    assert @target.body_overridden?
    assert_equal 2, @target.revision
    assert_equal due_at, @target.due_at
    assert_equal sibling_revision, @sibling.reload.revision
    assert_equal posts(:launch).body, @sibling.effective_body
  end

  test "fields passed as unchanged keep their value" do
    @target.edit_for_platform!(by: @editor, body: "Own text")
    @target.edit_for_platform!(by: @editor, provider_options: { "visibility" => "unlisted" })

    @target.reload
    assert_equal "Own text", @target.body_override
    assert_equal({ "visibility" => "unlisted" }, @target.provider_options)
  end

  test "reset to shared restores inheritance" do
    @target.edit_for_platform!(by: @editor, body: "Own text")
    @target.reset_body_to_shared!(by: @editor)

    assert_not @target.reload.body_overridden?
    assert_equal posts(:launch).body, @target.effective_body
  end

  test "shared edits reach only targets that inherit the text" do
    @target.edit_for_platform!(by: @editor, body: "Own text")
    revision = @target.reload.revision

    posts(:launch).update_shared_body!("New shared text", by: @editor)

    assert_equal "Own text", @target.reload.effective_body
    assert_equal revision, @target.revision
    assert_equal "New shared text", @sibling.reload.effective_body
    assert_equal 2, @sibling.revision
  end

  test "targets that are publishing or may be published cannot be edited" do
    @target.update!(state: "publishing")
    assert_raises(PostTarget::NotEditable) { @target.edit_for_platform!(by: @editor, body: "Too late") }

    @target.update!(state: "needs_attention", attention_reason: "publication_unconfirmed")
    assert_raises(PostTarget::NotEditable) { @target.edit_for_platform!(by: @editor, body: "Too late") }

    @target.update!(attention_reason: "schedule_missed")
    assert @target.edit_for_platform!(by: @editor, body: "Rescheduling with new text")
  end

  test "reasons must match the state, in the model and the database" do
    @target.state = "blocked"
    assert_not @target.valid?
    assert_includes @target.errors[:blocked_reason], "is required when the target is blocked"

    assert_raises(ActiveRecord::StatementInvalid) do
      @target.update_columns(state: "blocked", blocked_reason: nil)
    end
  end
end

# Scheduling a target (design specifications/02, Scheduling semantics).
class PostTargetSchedulingTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 23, 12, 0)

  setup do
    travel_to NOW
    @queue = channel_queues(:studio_bluesky)
    daily_slots!(@queue, "09:00")
    @target = new_target
  end

  test "a fixed time is stored with its wall-clock input and zone" do
    @target.schedule!(by: users(:bob), mode: "manual", local_at: Time.utc(2026, 10, 24, 12, 30),
                      timezone: "America/Toronto")

    assert @target.scheduled?
    assert @target.manual?
    assert_equal Time.utc(2026, 10, 24, 16, 30), @target.due_at
    assert_equal "America/Toronto", @target.scheduled_timezone
    assert_equal(-4 * 3600, @target.scheduled_utc_offset_seconds)
    assert OutboxEvent.exists?(event_type: "post_target.scheduled", subject_id: @target.id)
  end

  test "a repeated wall time needs the offset choice" do
    error = assert_raises(PostTarget::ScheduleError) do
      @target.schedule!(by: users(:bob), mode: "manual", local_at: Time.utc(2026, 11, 1, 1, 30))
    end
    assert_match(/happens twice/, error.message)

    @target.schedule!(by: users(:bob), mode: "manual", local_at: Time.utc(2026, 11, 1, 1, 30), utc_offset: -18_000)
    assert_equal Time.utc(2026, 11, 1, 6, 30), @target.due_at
  end

  test "times in the past are refused" do
    assert_raises(PostTarget::ScheduleError) do
      @target.schedule!(by: users(:bob), mode: "manual", local_at: Time.utc(2026, 10, 22, 9, 0))
    end
    assert @target.reload.draft?
  end

  test "switching from queue to a fixed time leaves the queue and moves the others up" do
    @target.schedule!(by: users(:bob), mode: "queue")
    other = queued_target

    @target.schedule!(by: users(:bob), mode: "manual", local_at: Time.utc(2026, 10, 30, 12, 0))

    assert_nil @target.queue_entry
    assert_equal Time.utc(2026, 10, 23, 13, 0), other.reload.due_at
  end

  test "publish now makes the target due immediately and notifies the dispatcher" do
    @target.publish_now!(by: users(:bob))

    assert @target.now?
    assert_equal NOW, @target.due_at
    assert OutboxEvent.exists?(event_type: "post_target.publish_requested", subject_id: @target.id)
  end

  test "rescheduling a missed target clears the attention reason" do
    @target.update!(mode: "manual", state: "needs_attention", attention_reason: "schedule_missed", due_at: NOW - 1.hour)

    @target.schedule!(by: users(:bob), mode: "manual", local_at: Time.utc(2026, 10, 24, 9, 0))

    assert @target.scheduled?
    assert_nil @target.attention_reason
  end

  test "a provider that requires media cannot schedule a text-only post" do
    plugin = @target.social_account.plugin
    plugin.update!(manifest: plugin.manifest.merge("capabilities" => { "requires_media" => true }))

    error = assert_raises(PostTarget::ScheduleError) { @target.reload.schedule!(by: users(:bob), mode: "queue") }
    assert_equal "Needs a photo or video", error.message
  end

  test "a target that may already be published cannot be rescheduled" do
    @target.update!(state: "needs_attention", attention_reason: "publication_unconfirmed")
    assert_raises(PostTarget::NotEditable) { @target.publish_now!(by: users(:bob)) }
  end

  test "editing content keeps the queue slot" do
    @target.schedule!(by: users(:bob), mode: "queue")
    slot = @target.due_at

    @target.edit_for_platform!(by: users(:bob), body: "Shorter")

    assert_equal slot, @target.reload.due_at
    assert_equal slot, @target.queue_entry.slot_occurrence_at
  end

  test "cancelling leaves the queue" do
    @target.schedule!(by: users(:bob), mode: "queue")
    @target.cancel!(by: users(:bob))

    assert @target.cancelled?
    assert_nil @target.queue_entry
    assert_nil @target.due_at
  end
end
