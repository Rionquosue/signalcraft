# frozen_string_literal: true

# The Queue landing page (design specifications/05, Queue view). Until account
# connections and scheduling are built, it shows the workspace's accounts
# and the empty states defined in sheet 05.
class DashboardController < ApplicationController
  def show
    @workspaces = current_user.workspaces.active.order(:name)
    @workspace = @workspaces.find_by(id: params[:workspace_id]) || @workspaces.first
    @accounts = @workspace ? @workspace.social_accounts.includes(:plugin, :channel_queue).order(:display_name) : []
  end
end
