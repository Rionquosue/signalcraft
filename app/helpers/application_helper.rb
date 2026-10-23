# frozen_string_literal: true

module ApplicationHelper
  # Visible labels from design specifications/05, Status language. The label
  # for needs_attention and blocked always comes from the stored reason.
  ATTENTION_LABELS = {
    "publication_unconfirmed" => "Publication unconfirmed",
    "schedule_missed" => "Schedule missed",
    "unsupported_checkpoint_version" => "Needs owner review"
  }.freeze
  BLOCKED_LABELS = {
    "plugin_unavailable" => "Plugin unavailable", "plugin_disabled" => "Plugin unavailable",
    "validation_failed" => "Needs changes", "budget_exhausted" => "Budget reached",
    "protected_media_incompatible" => "Protected image not accepted", "media_unavailable" => "Media not ready",
    "fetch_url_unavailable" => "Not available on this server"
  }.freeze
  STATE_TONES = {
    "published" => "success", "needs_attention" => "warn", "blocked" => "warn", "retry_wait" => "warn",
    "failed" => "danger", "cancelled" => "neutral", "draft" => "neutral"
  }.freeze

  def target_state_label(target, now: Time.current)
    case target.state
    when "draft" then "Draft"
    when "scheduled"
      late = target.due_at && target.due_at <= now
      return "Publishing shortly" if late && !target.social_account.channel_queue&.paused?

      target.queue? ? "Queued" : "Scheduled"
    when "preparing" then "Preparing media"
    when "publishing" then "Publishing"
    when "awaiting_provider" then "Processing on service"
    when "published" then "Published"
    when "retry_wait" then "Retry scheduled · #{display_time(target.retry_at, target.workspace.default_timezone)}"
    when "blocked" then BLOCKED_LABELS.fetch(target.blocked_reason, "Needs connection")
    when "needs_attention" then ATTENTION_LABELS.fetch(target.attention_reason)
    when "failed" then "Failed"
    when "cancelled" then "Cancelled"
    end
  end

  def state_badge(target)
    tag.span(target_state_label(target), class: ["badge", STATE_TONES[target.state]])
  end

  def mode_label(target)
    { "queue" => "Queue", "manual" => "Fixed time", "now" => "Now" }.fetch(target.mode)
  end

  # "23 Oct, 09:00" with the year added when it is not the current one.
  def display_time(time, zone)
    return "No slot yet" if time.nil?

    local = time.in_time_zone(zone)
    local.strftime(local.year == Time.current.in_time_zone(zone).year ? "%-d %b, %H:%M" : "%-d %b %Y, %H:%M")
  end

  # Tooltip text with the UTC offset (05, Scheduling and timezone interaction).
  def time_with_offset(time, zone)
    return nil if time.nil?

    local = time.in_time_zone(zone)
    "#{local.strftime('%-d %b %Y, %H:%M')} #{local.formatted_offset} (#{zone})"
  end

  def offset_label(seconds)
    sign = seconds.negative? ? "−" : "+"
    hours, rest = seconds.abs.divmod(3600)
    "UTC#{sign}#{hours}#{rest.zero? ? '' : format(':%02d', rest / 60)}"
  end

  def platform_name(account)
    account.plugin.manifest["name"] || account.plugin_id
  end
end
