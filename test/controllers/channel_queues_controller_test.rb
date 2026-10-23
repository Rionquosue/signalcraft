# frozen_string_literal: true

require "test_helper"

# Posting times, pause/resume and keyboard moves (design specifications/05, Queue
# view and Scheduling and timezone interaction; UI acceptance scenarios 3, 4 and 10).
class ChannelQueuesControllerTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 10, 23, 12, 0)

  setup do
    travel_to NOW
    @queue = channel_queues(:studio_bluesky)
    sign_in_as users(:bob)
  end

  test "posting times are saved per weekday and previewed with the DST rules" do
    patch channel_queue_path(@queue), params: { timezone: "America/Toronto", version: @queue.version,
                                                times: { "1" => "09:00, 15:30", "5" => "9:15" } }
    assert_redirected_to edit_channel_queue_path(@queue)
    assert_equal [[1, "09:00"], [1, "15:30"], [5, "09:15"]],
                 @queue.queue_slots.reload.map { |s| [s.iso_weekday, s.local_time.strftime("%H:%M")] }

    follow_redirect!
    assert_select ".occurrences li", 10
    assert_select "p", /happens twice when clocks move back runs once/
  end

  test "an invalid time is rejected without changing the slots" do
    daily_slots!(@queue, "09:00")
    patch channel_queue_path(@queue), params: { timezone: "America/Toronto", times: { "1" => "25:00" } }
    assert_redirected_to edit_channel_queue_path(@queue)
    assert_equal 7, @queue.queue_slots.count
    assert_match(/25:00 on Monday is not a time/, flash[:alert])
  end

  test "moving a queued post previews the changed dates, then commits" do
    daily_slots!(@queue, "09:00")
    first, second = 2.times.map { queued_target }

    get new_channel_queue_move_path(@queue, entry_id: second.queue_entry.id, direction: "up")
    assert_response :success
    assert_select "tbody tr", 2
    order = css_select("input[name='order[]']").map { |input| input["value"] }

    post channel_queue_moves_path(@queue), params: { order: order, version: @queue.reload.version }
    assert_redirected_to root_path(workspace_id: @queue.workspace_id)
    assert_equal Time.utc(2026, 10, 23, 13, 0), second.reload.due_at
    assert_equal Time.utc(2026, 10, 24, 13, 0), first.reload.due_at
  end

  test "a move against a changed queue is refused and can be retried" do
    daily_slots!(@queue, "09:00")
    first, second = 2.times.map { queued_target }
    stale = @queue.reload.version
    queued_target

    post channel_queue_moves_path(@queue), params: { order: [second.queue_entry.id, first.queue_entry.id],
                                                     version: stale, entry_id: second.queue_entry.id,
                                                     direction: "up" }
    assert_equal "This queue changed. Review the updated order.", flash[:alert]
    follow_redirect!
    assert_select ".banner a", "Try the move again"
    assert_equal Time.utc(2026, 10, 23, 13, 0), first.reload.due_at
  end

  test "pausing and resuming with a preview of what moves" do
    daily_slots!(@queue, "09:00")
    target = queued_target
    post pause_channel_queue_path(@queue)
    assert @queue.reload.paused?

    travel_to NOW + 1.day + 2.hours
    get resume_channel_queue_path(@queue)
    assert_select "h2", "Queued posts that move to their next slot"

    post resume_channel_queue_path(@queue)
    assert_not @queue.reload.paused?
    assert_match(/1 queued post moved to the next slot/, flash[:notice])
    assert_operator target.reload.due_at, :>, Time.current
  end

  test "viewers can see posting times but not change them" do
    viewer = User.create!(email: "viewer@example.com", display_name: "Viewer", password: ActiveSupport::TestCase::PASSWORD)
    Membership.create!(workspace: workspaces(:studio), user: viewer, role: "viewer")
    sign_in_as viewer

    get edit_channel_queue_path(@queue)
    assert_response :success
    assert_select "input[type=submit]", 0

    post pause_channel_queue_path(@queue)
    assert_not @queue.reload.paused?
  end
end
