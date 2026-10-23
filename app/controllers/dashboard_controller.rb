# frozen_string_literal: true

# The Queue landing page (design specifications/05, Queue view): one column
# per account showing its publication targets, not shared posts.
class DashboardController < ApplicationController
  include WorkspaceAccess

  # Targets shown on the queue; published, failed and cancelled ones belong
  # to History.
  QUEUE_STATES = %w[scheduled preparing publishing awaiting_provider retry_wait blocked needs_attention].freeze

  def show
    @workspaces = current_user.workspaces.active.order(:name)
    @workspace = @workspaces.find_by(id: params[:workspace_id]) || @workspaces.first
    return unless @workspace

    @can_publish = membership_for(@workspace.id).can_publish?
    @accounts = @workspace.social_accounts.includes(:plugin, :channel_queue).order(:display_name)
    targets = @workspace.post_targets.where(state: QUEUE_STATES).includes(:post, :queue_entry, :social_account)
                        .order(Arel.sql("due_at IS NULL, due_at"))
    @targets_by_account = targets.group_by(&:social_account_id)
    @waiting_ids = @accounts.filter_map(&:channel_queue).to_h { |queue| [queue.id, queue.waiting_entries.map(&:id)] }
  end
end
