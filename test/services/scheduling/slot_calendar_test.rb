# frozen_string_literal: true

require "test_helper"

# Queue slot occurrences across daylight-saving changes
# (design specifications/02 and 05: nonexistent slots are skipped; repeated
# slots run once, at the first occurrence).
class SlotCalendarTest < ActiveSupport::TestCase
  Slot = Struct.new(:iso_weekday, :local_time)

  def slot(weekday, hhmm)
    hour, minute = hhmm.split(":").map(&:to_i)
    Slot.new(weekday, Time.utc(2000, 1, 1, hour, minute))
  end

  def times(zone, slots, after, count)
    Scheduling::SlotCalendar.new(zone, slots).next_occurrences(after: after, count: count).map(&:at)
  end

  test "occurrences follow weekdays and local times in order" do
    slots = [slot(5, "09:00"), slot(1, "12:30"), slot(5, "17:00")] # Fri 09:00, Mon 12:30, Fri 17:00
    after = Time.utc(2026, 10, 23, 12, 0) # Friday 08:00 in Toronto
    assert_equal [
      Time.utc(2026, 10, 23, 13, 0), Time.utc(2026, 10, 23, 21, 0), Time.utc(2026, 10, 26, 16, 30),
      Time.utc(2026, 10, 30, 13, 0)
    ], times("America/Toronto", slots, after, 4)
  end

  test "occurrences are strictly after the given instant" do
    after = Time.utc(2026, 10, 23, 13, 0)
    assert_equal Time.utc(2026, 10, 30, 13, 0), times("America/Toronto", [slot(5, "09:00")], after, 1).first
  end

  test "a slot in the spring-forward gap is skipped that day" do
    after = Time.utc(2026, 3, 1, 0, 0)
    assert_equal [Time.utc(2026, 3, 1, 7, 30), Time.utc(2026, 3, 15, 6, 30)],
                 times("America/Toronto", [slot(7, "02:30")], after, 2)
  end

  test "a slot in the repeated hour runs once, at its first occurrence" do
    after = Time.utc(2026, 10, 24, 0, 0)
    assert_equal [Time.utc(2026, 10, 25, 5, 30), Time.utc(2026, 11, 1, 5, 30), Time.utc(2026, 11, 8, 6, 30)],
                 times("America/Toronto", [slot(7, "01:30")], after, 3)
  end

  test "zones east of UTC use their own local day" do
    # Monday 08:00 in Tokyo is Sunday 23:00 UTC.
    after = Time.utc(2026, 10, 25, 0, 0)
    assert_equal [Time.utc(2026, 10, 25, 23, 0)], times("Asia/Tokyo", [slot(1, "08:00")], after, 1)
  end

  test "no slots means no occurrences" do
    assert_empty times("America/Toronto", [], Time.utc(2026, 1, 1), 3)
  end
end
