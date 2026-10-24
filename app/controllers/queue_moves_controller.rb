# frozen_string_literal: true

# Keyboard-accessible Move up / Move down for queued targets. A move is
# previewed with its changed dates, then committed against the queue
# version it was previewed with (design specifications/05, Queue view).
class QueueMovesController < ApplicationController
  include WorkspaceAccess

  before_action :set_queue
  before_action -> { require_publisher!(@queue.workspace_id) }

  def new
    @order = @queue.order_after_move(params.require(:entry_id), params.require(:direction))
    @changes = @queue.allocator.plan(order: @order).select(&:moved?)
    @version = @queue.version
  end

  def create
    @queue.reorder!(Array(params[:order]), expected_version: params.require(:version), by: current_user)
    redirect_to root_path(workspace_id: @queue.workspace_id), notice: "Queue order saved."
  rescue Scheduling::QueueAllocator::StaleQueue => e
    # Keep the intended move so it can be retried against the new order.
    redirect_to root_path(workspace_id: @queue.workspace_id, retry_entry: params[:entry_id],
                          retry_direction: params[:direction]),
                alert: e.message
  end

  private

  def set_queue
    @queue = accessible(ChannelQueue).find(params[:channel_queue_id])
  end
end
