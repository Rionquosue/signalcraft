# frozen_string_literal: true

module Scheduling
  # Turns a wall-clock time in an IANA time zone into a UTC instant, following
  # the project's daylight-saving rules (design specifications/02, Scheduling
  # semantics; 05, Scheduling and timezone interaction):
  #
  # - a time that does not exist (clocks jump forward over it) is rejected,
  #   and the next valid wall time is offered;
  # - a time that happens twice (clocks fall back) needs an explicit UTC
  #   offset, which picks one of the two instants.
  module WallClock
    class Nonexistent < StandardError
      attr_reader :next_valid_local

      def initialize(local, next_valid_local)
        @next_valid_local = next_valid_local
        super("#{local.strftime('%-d %b %Y, %H:%M')} does not exist in this time zone (clocks move forward); " \
              "the next valid time is #{next_valid_local.strftime('%H:%M')}")
      end
    end

    class Ambiguous < StandardError
      # UTC offsets in seconds, earliest instant (first occurrence) first.
      attr_reader :offsets

      def initialize(local, offsets)
        @offsets = offsets
        super("#{local.strftime('%-d %b %Y, %H:%M')} happens twice in this time zone (clocks move back); " \
              "choose which one")
      end
    end

    module_function

    def tzinfo(name)
      zone = ActiveSupport::TimeZone[name.to_s] or raise ArgumentError, "unknown time zone #{name.inspect}"
      zone.tzinfo
    end

    # Floating wall-clock value (a UTC-flagged Time holding local fields), the
    # same representation as the scheduled_local_at column.
    def local(year, month, day, hour, minute, second = 0)
      Time.utc(year, month, day, hour, minute, second)
    end

    # The UTC offsets (seconds) at which `local` exists in `zone`, earliest
    # instant first. Empty when the wall time is skipped by a transition.
    def offsets_for(zone, local)
      tzinfo(zone).periods_for_local(local).map(&:utc_total_offset).uniq.sort.reverse
    end

    # UTC instant for a manual time. `utc_offset` (seconds) is required only
    # when the wall time is ambiguous, and must be one of its offsets.
    def resolve(zone, local, utc_offset: nil)
      offsets = offsets_for(zone, local)
      raise Nonexistent.new(local, next_valid(zone, local)) if offsets.empty?

      offset =
        if offsets.one?
          offsets.first
        elsif utc_offset && offsets.include?(utc_offset.to_i)
          utc_offset.to_i
        else
          raise Ambiguous.new(local, offsets)
        end
      local - offset
    end

    # The UTC instant of the first occurrence of a wall time, or nil if it
    # does not exist. Used for queue slots.
    def first_occurrence(zone, local)
      offset = offsets_for(zone, local).first
      offset && local - offset
    end

    # First wall time after a skipped one that exists (the end of the gap).
    def next_valid(zone, local)
      candidate = local
      # Gaps are at most a few hours in practice; 24 hours bounds the search.
      (24 * 60).times do
        candidate += 60
        return candidate unless offsets_for(zone, candidate).empty?
      end
      raise ArgumentError, "no valid time found after #{local}"
    end
  end
end
