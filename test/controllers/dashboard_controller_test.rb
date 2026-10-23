# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires sign-in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "shows the workspace's accounts" do
    sign_in_as users(:alice)
    get root_path
    assert_response :success
    assert_select "h2", "Studio"
    assert_select ".empty", /Choose posting times for this account/
    assert_select ".card", 2
  end

  test "shows a paused account indicator" do
    channel_queues(:studio_bluesky).pause!(by: users(:alice))
    sign_in_as users(:alice)
    get root_path
    assert_select ".indicator", "Account paused"
  end

  test "a workspace with no accounts shows the connect prompt" do
    user = User.create!(email: "new@example.com", display_name: "New", password: ActiveSupport::TestCase::PASSWORD)
    Membership.create!(workspace: workspaces(:other), user: user, role: "owner")
    sign_in_as user
    get root_path
    assert_select ".empty", /Connect an account to start scheduling/
  end

  test "queue cards show time, state, mode and per-platform edits" do
    travel_to Time.utc(2026, 10, 23, 12, 0) do
      daily_slots!(channel_queues(:studio_bluesky), "09:00")
      first = queued_target(body: "First queued")
      queued_target(body: "Second queued")
      first.edit_for_platform!(by: users(:bob), body: "Own copy")

      sign_in_as users(:bob)
      get root_path
      assert_select ".card", 4 # two queued and two fixed-time fixture targets
      assert_select ".card .badge", /Queued/
      assert_select ".card .badge", "Edited for Bluesky"
      assert_select ".card .mode", /Fixed time/
      assert_select ".card a", "Move down"
      assert_select ".card a", "Move up"
      assert_select ".card a", text: "Edit for Bluesky"
    end
  end

  test "a late target inside the grace window reads Publishing shortly" do
    post_targets(:launch_bluesky).update!(due_at: 2.minutes.ago)
    sign_in_as users(:alice)
    get root_path
    assert_select ".card .badge", "Publishing shortly"
  end
end
