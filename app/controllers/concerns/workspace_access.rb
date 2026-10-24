# frozen_string_literal: true

# Workspace authorization for every record a request touches. Records are
# always looked up through the signed-in user's memberships, so an ID from
# another workspace is simply not found (design specifications/02, Durable
# data model: IDs alone confer no access). Viewers may look; only owners and
# editors may compose and schedule (05, Plugin-driven UI).
module WorkspaceAccess
  extend ActiveSupport::Concern

  class Forbidden < StandardError; end

  included do
    rescue_from Forbidden do
      redirect_back_or_to root_path, alert: "Your role in this workspace can't make that change."
    end
  end

  private

  def accessible_workspace_ids
    current_user.memberships.joins(:workspace).merge(Workspace.active).select(:workspace_id)
  end

  # `scope` limited to the signed-in user's active workspaces.
  def accessible(scope)
    scope.where(workspace_id: accessible_workspace_ids)
  end

  # The requested workspace, or the user's first one by name.
  def selected_workspace(workspace_id)
    workspaces = current_user.workspaces.active
    workspaces.find_by(id: workspace_id) || workspaces.order(:name).first
  end

  def membership_for(workspace_id)
    @memberships ||= {}
    @memberships[workspace_id] ||= current_user.memberships.find_by!(workspace_id: workspace_id)
  end

  def publisher?(workspace_id)
    membership_for(workspace_id).can_publish?
  end

  def require_publisher!(workspace_id)
    raise Forbidden unless publisher?(workspace_id)
  end
end
