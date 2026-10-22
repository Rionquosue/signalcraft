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
    assert_select ".empty", /Your queue is clear/
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
end
