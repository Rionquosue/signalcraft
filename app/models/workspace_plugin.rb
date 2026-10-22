# frozen_string_literal: true

# A workspace's enablement and settings for one installed addon.
class WorkspacePlugin < ApplicationRecord
  self.primary_key = %i[workspace_id plugin_id]

  belongs_to :workspace
  belongs_to :plugin, foreign_key: :plugin_id, primary_key: :plugin_id, inverse_of: :workspace_plugins
  belongs_to :enabled_by, class_name: "User", optional: true

  scope :enabled, -> { where(enabled: true) }
end
