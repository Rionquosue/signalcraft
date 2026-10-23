# frozen_string_literal: true

module Scheduling
  # Concrete occurrences of a queue's recurring slots, evaluated in the
  # queue's time zone (design specifications/02, Scheduling semantics).
  # A slot on a skipped wall time does not occur that day; a slot on a
  # repeated wall time occurs once, at its first occurrence.
  class SlotCalendar
    Occurrence = Struct.new(:slot, :at, keyword_init: true)

    # How far ahead to look before giving up (for example when every slot
    # falls in a gap, which cannot last this long).
    HORIZON_DAYS = 400

    def initialize(timezone, slots)
      @timezone = timezone
      @slots_by_weekday = slots.group_by(&:iso_weekday).transform_values { |list| list.sort_by { |s| seconds_of(s) } }
      @tz = WallClock.tzinfo(timezone)
    end

    # Lazily yields Occurrence values strictly after `after`, earliest first.
    def occurrences(after:)
      return [].lazy if @slots_by_weekday.empty?

      Enumerator.new do |yielder|
        date = @tz.utc_to_local(after.utc).to_date - 1 # the day before covers offsets west of UTC
        HORIZON_DAYS.times do
          day_occurrences(date).each { |occurrence| yielder << occurrence if occurrence.at > after }
          date += 1
        end
      end.lazy
    end

    def next_occurrences(after:, count:)
      occurrences(after: after).first(count)
    end

    private

    def day_occurrences(date)
      slots = @slots_by_weekday[date.cwday] || []
      slots.filter_map do |slot|
        seconds = seconds_of(slot)
        local = WallClock.local(date.year, date.month, date.day, seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        at = WallClock.first_occurrence(@timezone, local)
        Occurrence.new(slot: slot, at: at) if at
      end.sort_by(&:at)
    end

    # local_time is a time-of-day column; Rails reads it as a Time on 2000-01-01.
    def seconds_of(slot)
      time = slot.local_time
      (time.hour * 3600) + (time.min * 60) + time.sec
    end
  end
end
