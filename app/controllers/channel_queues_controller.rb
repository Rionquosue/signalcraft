# frozen_string_literal: true

# Queue slots, pause and resume for one account (design specifications/05,
# Scheduling and timezone interaction).
class ChannelQueuesController < ApplicationController
  include WorkspaceAccess

  WEEKDAYS = { 1 => "Monday", 2 => "Tuesday", 3 => "Wednesday", 4 => "Thursday", 5 => "Friday", 6 => "Saturday",
               7 => "Sunday" }.freeze

  before_action :set_queue
  before_action -> { require_publisher!(@queue.workspace_id) }, except: :edit

  rescue_from Scheduling::QueueAllocator::StaleQueue do |error|
    redirect_to edit_channel_queue_path(@queue), alert: error.message
  end

  def edit
    @can_publish = membership_for(@queue.workspace_id).can_publish?
    @times = @queue.queue_slots.group_by(&:iso_weekday)
                   .transform_values { |slots| slots.map { |s| s.local_time.strftime("%H:%M") }.join(", ") }
    @preview = @queue.next_occurrences(count: 10)
  end

  def update
    slots, errors = parse_slots(params.fetch(:times, {}))
    timezone = params[:timezone].to_s
    errors << "Choose a known time zone" unless ActiveSupport::TimeZone[timezone]
    if errors.any?
      redirect_to edit_channel_queue_path(@queue), alert: errors.join(". ")
      return
    end

    @queue.replace_slots!(slots, timezone: timezone, by: current_user, expected_version: params[:version])
    redirect_to edit_channel_queue_path(@queue), notice: "Posting times saved. Queued posts moved to the new times."
  end

  def pause
    @queue.pause!(by: current_user)
    redirect_back_or_to root_path, notice: "#{@queue.social_account.display_name} paused."
  end

  def resume_preview
    @preview = @queue.resume_preview
  end

  def resume
    result = @queue.resume!(by: current_user)
    notice = "#{@queue.social_account.display_name} resumed."
    notice += " #{helpers.pluralize(result.moved.size, 'queued post')} moved to the next slot." if result.moved.any?
    notice += " #{helpers.pluralize(result.missed.size, 'fixed-time post')} need a decision." if result.missed.any?
    redirect_to root_path(workspace_id: @queue.workspace_id), notice: notice
  end

  private

  def set_queue
    @queue = ChannelQueue.where(workspace_id: accessible_workspace_ids).find(params[:id])
    membership_for(@queue.workspace_id)
  end

  # times: { "1" => "09:00, 15:30", ... } -> [[1, "09:00"], [1, "15:30"], ...]
  def parse_slots(times)
    errors = []
    slots = WEEKDAYS.keys.flat_map do |weekday|
      times[weekday.to_s].to_s.split(/[,\s]+/).reject(&:blank?).filter_map do |value|
        if value.match?(/\A([01]?\d|2[0-3]):[0-5]\d\z/)
          [weekday, format("%05s", value).tr(" ", "0")]
        else
          errors << "#{value} on #{WEEKDAYS[weekday]} is not a time (use HH:MM)"
          nil
        end
      end
    end
    [slots, errors]
  end
end
