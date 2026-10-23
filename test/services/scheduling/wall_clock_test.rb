# frozen_string_literal: true

require "test_helper"

# Daylight-saving rules for manual times (design specifications/02, Scheduling semantics).
# America/Toronto in 2026: clocks jump 02:00 -> 03:00 on 8 March and fall
# back 02:00 -> 01:00 on 1 November.
class WallClockTest < ActiveSupport::TestCase
  ZONE = "America/Toronto"

  def local(*args)
    Scheduling::WallClock.local(*args)
  end

  test "an ordinary wall time resolves with the zone's offset" do
    assert_equal Time.utc(2026, 10, 23, 13, 0), Scheduling::WallClock.resolve(ZONE, local(2026, 10, 23, 9, 0))
  end

  test "a skipped wall time is rejected with the next valid time" do
    error = assert_raises(Scheduling::WallClock::Nonexistent) do
      Scheduling::WallClock.resolve(ZONE, local(2026, 3, 8, 2, 30))
    end
    assert_equal local(2026, 3, 8, 3, 0), error.next_valid_local
    assert_match(/next valid time is 03:00/, error.message)
  end

  test "a repeated wall time needs an offset choice" do
    error = assert_raises(Scheduling::WallClock::Ambiguous) do
      Scheduling::WallClock.resolve(ZONE, local(2026, 11, 1, 1, 30))
    end
    assert_equal [-4 * 3600, -5 * 3600], error.offsets # first occurrence (EDT) first
  end

  test "the chosen offset picks one of the two instants" do
    first = Scheduling::WallClock.resolve(ZONE, local(2026, 11, 1, 1, 30), utc_offset: -4 * 3600)
    second = Scheduling::WallClock.resolve(ZONE, local(2026, 11, 1, 1, 30), utc_offset: -5 * 3600)
    assert_equal Time.utc(2026, 11, 1, 5, 30), first
    assert_equal Time.utc(2026, 11, 1, 6, 30), second
  end

  test "an offset that does not apply is not accepted" do
    assert_raises(Scheduling::WallClock::Ambiguous) do
      Scheduling::WallClock.resolve(ZONE, local(2026, 11, 1, 1, 30), utc_offset: 0)
    end
  end

  test "first_occurrence skips gaps and takes the earlier repeated instant" do
    assert_nil Scheduling::WallClock.first_occurrence(ZONE, local(2026, 3, 8, 2, 30))
    assert_equal Time.utc(2026, 11, 1, 5, 30), Scheduling::WallClock.first_occurrence(ZONE, local(2026, 11, 1, 1, 30))
  end
end
