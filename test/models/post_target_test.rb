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
