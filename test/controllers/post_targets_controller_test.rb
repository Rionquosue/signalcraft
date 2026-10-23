# frozen_string_literal: true

require "test_helper"

# Editing one platform's copy (design specifications/05, Editing a queued post for one platform).
class PostTargetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @target = post_targets(:launch_bluesky)
    @sibling = post_targets(:launch_bluesky_again)
    sign_in_as users(:bob)
  end

  test "saving text for one platform changes only that target" do
    due_at = @target.due_at

    patch post_target_path(@target), params: { post_target: { body: "Short copy" } }

    assert_redirected_to edit_post_path(@target.post, target: @target.id)
    assert_equal "Short copy", @target.reload.body_override
    assert_equal due_at, @target.due_at
    assert_nil @sibling.reload.body_override
  end

  test "submitting the shared text unchanged keeps inheriting" do
    patch post_target_path(@target), params: { post_target: { body: @target.post.body } }
    assert_not @target.reload.body_overridden?
    assert_equal 1, @target.revision
  end

  test "the platform tab marks edited text and offers reset to shared" do
    @target.edit_for_platform!(by: users(:bob), body: "Own")
    get edit_post_path(@target.post, target: @target.id)
    assert_select ".platform .badge", "Edited for Bluesky"
    assert_select "form[action='#{body_post_target_path(@target)}']"

    delete body_post_target_path(@target)
    assert_not @target.reload.body_overridden?
  end

  test "an in-flight target offers a copy instead of editing" do
    @target.update!(state: "publishing")
    get edit_post_path(@target.post, target: @target.id)
    assert_select ".platform textarea", 0
    assert_select ".platform button", "Copy to new draft"

    patch post_target_path(@target), params: { post_target: { body: "Too late" } }
    assert_nil @target.reload.body_override

    assert_difference -> { Post.count } do
      post copy_post_target_path(@target)
    end
    assert @target.reload.publishing?
  end

  test "a missed fixed-time target can be published now" do
    @target.update!(state: "needs_attention", attention_reason: "schedule_missed")
    use_fake_addon!

    assert_enqueued_with(job: DispatchJob) { post publish_now_post_target_path(@target) }
    assert @target.reload.scheduled?
    assert @target.now?
  end

  test "targets in other workspaces are not found" do
    sign_in_as users(:alice)
    other_post = Post.create!(workspace: workspaces(:other), body: "x")
    registration = plugin_app_registrations(:bsky)
    account = SocialAccount.create!(workspace: workspaces(:other), plugin_id: "bluesky", plugin_app_registration: registration,
                                    provider_account_id: "did:plc:x", display_name: "X", credentials: "{}",
                                    connection_status: "connected")
    target = PostTarget.create!(workspace: workspaces(:other), post: other_post, social_account: account, mode: "queue",
                                state: "draft")
    patch post_target_path(target), params: { post_target: { body: "nope" } }
    assert_response :not_found
  end
end
