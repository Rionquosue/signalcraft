# frozen_string_literal: true

# One installed addon, synced from the plugins directory
# (SignalCraft::Plugins::Registry, PluginRegistrySync).
class Plugin < ApplicationRecord
  self.primary_key = "plugin_id"

  string_enum :kind, %w[social commerce]
  string_enum :load_status, %w[loaded failed missing], prefix: :status

  has_many :workspace_plugins, inverse_of: :plugin, dependent: :restrict_with_error
  has_many :plugin_app_registrations, inverse_of: :plugin, dependent: :restrict_with_error
  has_many :social_accounts, inverse_of: :plugin, dependent: :restrict_with_error

  def usable?
    status_loaded?
  end
end
