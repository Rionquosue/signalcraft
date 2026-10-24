# frozen_string_literal: true

# The composer's schedule table: one row per target with its mode and time
# (design specifications/05, Composer and independent publishing times).
# Rows are checked together before anything is scheduled, so an invalid row
# stops the combined action instead of being silently skipped.
class Composer
  Row = Struct.new(:target, :mode, :local_at, :timezone, :utc_offset, :error, :offsets, :next_valid,
                   keyword_init: true) do
    def ready?
      error.nil?
    end

    def local_value
      local_at&.strftime("%Y-%m-%dT%H:%M")
    end
  end

  attr_reader :post, :rows

  # `params`: { target_id => { mode:, local_at: "YYYY-MM-DDTHH:MM", timezone:, utc_offset: } }
  def initialize(post, params = {}, now: Time.current)
    @post = post
    @now = now
    @rows = post.post_targets.includes(:social_account, :queue_entry)
                .order("social_accounts.display_name", :occurrence).references(:social_account).map do |target|
      build_row(target, params.fetch(target.id, nil) || {})
    end
  end

  def check!
    rows.each { |row| row.error = problem_for(row) }
    self
  end

  # Rows the footer action applies to; published or in-flight targets are
  # shown but never rescheduled from here.
  def actionable_rows
    rows.select { |row| row.target.editable? }
  end

  def ready_rows
    actionable_rows.select(&:ready?)
  end

  def all_ready?
    actionable_rows.all?(&:ready?)
  end

  def now_rows
    ready_rows.select { |row| row.mode == "now" }
  end

  # Schedules every row, or only the ready ones; the rest stay draft.
  # Returns the number scheduled.
  def schedule!(by:, only_ready: false)
    check!
    return 0 unless only_ready || all_ready?

    ready_rows.count do |row|
      row.target.schedule!(by: by, mode: row.mode, local_at: row.local_at, timezone: row.timezone,
                           utc_offset: row.utc_offset, now: @now)
    rescue PostTarget::ScheduleError, PostTarget::NotEditable => e
      row.error = e.message
      false
    end
  end

  # "Save draft": keeps the chosen mode and time on draft targets without
  # scheduling them.
  def save_choices!(by:)
    rows.each do |row|
      next unless row.target.draft? && PostTarget::MODES.include?(row.mode)

      manual = row.mode == "manual"
      row.target.update!(mode: row.mode, scheduled_local_at: manual ? row.local_at : nil,
                         scheduled_timezone: manual && row.local_at ? row.timezone : nil,
                         scheduled_utc_offset_seconds: manual ? row.utc_offset : nil, updater: by)
    end
  end

  def self.parse_local(value)
    return nil if value.blank?

    match = value.to_s.match(/\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})\z/) or return nil
    Scheduling::WallClock.local(*match.captures.map(&:to_i))
  rescue ArgumentError
    nil
  end

  private

  def build_row(target, values)
    values = values.to_h.symbolize_keys
    timezone = values[:timezone].presence || target.scheduled_timezone || target.social_account.timezone
    local_at = values.key?(:local_at) ? self.class.parse_local(values[:local_at]) : target.scheduled_local_at
    Row.new(target: target, mode: values[:mode].presence || target.mode, local_at: local_at, timezone: timezone,
            utc_offset: values[:utc_offset].presence&.to_i || target.scheduled_utc_offset_seconds)
  end

  def problem_for(row)
    return nil unless row.target.editable?
    scheduling_problem = row.target.scheduling_problem
    return scheduling_problem if scheduling_problem
    return "Choose Queue, Fixed time or Now" unless PostTarget::MODES.include?(row.mode)
    return nil unless row.mode == "manual"
    return "Choose a date and time" if row.local_at.nil?
    return "Unknown time zone" unless ActiveSupport::TimeZone[row.timezone.to_s]

    due = Scheduling::WallClock.resolve(row.timezone, row.local_at, utc_offset: row.utc_offset)
    "Choose a time in the future" if due <= @now
  rescue Scheduling::WallClock::Nonexistent => e
    row.next_valid = e.next_valid_local
    e.message
  rescue Scheduling::WallClock::Ambiguous => e
    row.offsets = e.offsets
    e.message
  end
end
