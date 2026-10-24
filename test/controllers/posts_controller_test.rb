# frozen_string_literal: true

require "test_helper"

# The composer (design specifications/05, Composer and independent publishing times;
# UI acceptance scenarios 1, 2, 11 and 12).
class PostsControllerTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 10, 23, 12, 0)

  setup do
    travel_to NOW
    daily_slots!(channel_queues(:studio_bluesky), "09:00")
    @second = SocialAccount.create!(workspace: workspaces(:studio), plugin_id: "bluesky",
                                    plugin_app_registration: plugin_app_registrations(:bsky),
                                    provider_account_id: "did:plc:second", display_name: "Second",
                                    credentials: "{}", connection_status: "connected")
    sign_in_as users(:bob)
  end

  def create_post(accounts = [social_accounts(:studio_bluesky), @second], body: "Shared launch text")
    before = Post.ids
    post posts_path, params: { workspace_id: workspaces(:studio).id, account_ids: accounts.map(&:id),
                               post: { body: body } }
    Post.where.not(id: before).sole
  end

  def targets_of(post_record)
    [post_record.post_targets.find_by!(social_account: social_accounts(:studio_bluesky)),
     post_record.post_targets.find_by!(social_account: @second)]
  end

  def schedule(post_record, rows, commit: "schedule", **extra)
    patch post_path(post_record), params: { post: { body: post_record.body }, schedule: rows, commit_action: commit,
                                            **extra }
  end

  test "the composer lists the workspace's accounts" do
    get new_post_path(workspace_id: workspaces(:studio).id)
    assert_response :success
    assert_select "input[name='account_ids[]']", 2
  end

  test "creating a post makes one draft target per selected account" do
    record = create_post
    assert_redirected_to edit_post_path(record)
    assert_equal 2, record.post_targets.count
    assert record.post_targets.all?(&:draft?)

    follow_redirect!
    assert_select ".tab", 2
    assert_select "table.schedule tbody tr", 2
  end

  test "each account is scheduled independently from one draft" do
    record = create_post
    queued, fixed = targets_of(record)

    schedule(record, { queued.id => { mode: "queue" },
                       fixed.id => { mode: "manual", local_at: "2026-10-24T12:30", timezone: "America/Toronto" } })

    assert_redirected_to root_path(workspace_id: record.workspace_id)
    assert queued.reload.scheduled?
    assert_equal Time.utc(2026, 10, 23, 13, 0), queued.due_at
    assert_equal Time.utc(2026, 10, 24, 16, 30), fixed.reload.due_at
    assert_equal 1, Post.count - posts.count # one shared draft, not one per account
  end

  test "one invalid row stops the combined action and offers ready targets only" do
    record = create_post
    good, bad = targets_of(record)

    schedule(record, { good.id => { mode: "queue" },
                       bad.id => { mode: "manual", local_at: "2027-03-14T02:30", timezone: "America/Toronto" } })

    assert_response :unprocessable_content
    assert_select "tr.invalid .error-text", /does not exist/
    assert_select "button[value=schedule_ready]", "Schedule 1 ready only"
    assert good.reload.draft?

    schedule(record, { good.id => { mode: "queue" },
                       bad.id => { mode: "manual", local_at: "2027-03-14T02:30", timezone: "America/Toronto" } },
             commit: "schedule_ready")
    assert good.reload.scheduled?
    assert bad.reload.draft?
  end

  test "a repeated wall time asks which occurrence is meant" do
    record = create_post([social_accounts(:studio_bluesky)])
    target = record.post_targets.sole
    row = { mode: "manual", local_at: "2026-11-01T01:30", timezone: "America/Toronto" }

    schedule(record, { target.id => row })
    assert_response :unprocessable_content
    assert_select "select[name='schedule[#{target.id}][utc_offset]'] option", 2

    schedule(record, { target.id => row.merge(utc_offset: "-18000") })
    assert_equal Time.utc(2026, 11, 1, 6, 30), target.reload.due_at
  end

  test "publishing now asks for confirmation and names the accounts" do
    record = create_post
    now_target, later = targets_of(record)
    rows = { now_target.id => { mode: "now" }, later.id => { mode: "queue" } }

    schedule(record, rows)
    assert_response :success
    assert_select ".confirm", /Studio.*will publish now/m
    assert now_target.reload.draft?

    assert_enqueued_with(job: DispatchJob) { schedule(record, rows, confirmed_now: "1") }
    assert now_target.reload.now?
    assert now_target.scheduled?
    assert later.reload.scheduled?
  end

  test "text-only posts cannot be scheduled to providers that require media" do
    plugin = plugins(:bluesky)
    plugin.update!(manifest: plugin.manifest.merge("capabilities" => { "requires_media" => true }))
    record = create_post([social_accounts(:studio_bluesky)])

    schedule(record, { record.post_targets.sole.id => { mode: "queue" } })

    assert_response :unprocessable_content
    assert_select ".error-text", "Needs a photo or video"
  end

  test "saving a draft keeps the chosen mode and time without scheduling" do
    record = create_post([social_accounts(:studio_bluesky)])
    target = record.post_targets.sole

    schedule(record, { target.id => { mode: "manual", local_at: "2026-10-30T10:00", timezone: "America/Toronto" } },
             commit: "draft")

    target.reload
    assert target.draft?
    assert target.manual?
    assert_equal Time.utc(2026, 10, 30, 10, 0), target.scheduled_local_at
  end

  test "editing the shared text reaches only targets without their own text" do
    record = create_post
    own, inheriting = targets_of(record)
    own.edit_for_platform!(by: users(:bob), body: "Own words")

    patch post_path(record), params: { post: { body: "New shared text" }, commit_action: "draft" }

    assert_equal "Own words", own.reload.effective_body
    assert_equal "New shared text", inheriting.reload.effective_body
  end

  test "viewers cannot compose" do
    viewer = User.create!(email: "viewer@example.com", display_name: "Viewer", password: ActiveSupport::TestCase::PASSWORD)
    Membership.create!(workspace: workspaces(:studio), user: viewer, role: "viewer")
    sign_in_as viewer

    get new_post_path(workspace_id: workspaces(:studio).id)
    assert_redirected_to root_path
    assert_no_difference -> { Post.count } do
    before = Post.ids
      post posts_path, params: { workspace_id: workspaces(:studio).id, account_ids: [@second.id] }
    end
  end

  test "posts in other workspaces are not found" do
    other = Post.create!(workspace: workspaces(:other), body: "Private")
    get edit_post_path(other)
    assert_response :not_found
  end
end
