# frozen_string_literal: true

# A workspace's enablement and settings for one installed addon.
class WorkspacePlugin < ApplicationRecord
  self.primary_key = %i[workspace_id plugin_id]

  belongs_to :workspace
  belongs_to :plugin, inverse_of: :workspace_plugins
  belongs_to :enabler, class_name: "User", foreign_key: :enabled_by, optional: true

  scope :enabled, -> { where(enabled: true) }
end
