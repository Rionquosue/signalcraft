# frozen_string_literal: true

# The provider app a connection signs in through (design specifications/08):
# operator-configured for most providers, stored per instance for Mastodon.
class PluginAppRegistration < ApplicationRecord
  belongs_to :plugin, inverse_of: :plugin_app_registrations
  has_many :social_accounts, dependent: :restrict_with_error

  string_enum :credentials_source, %w[stored operator_config]
  encrypts :client_credentials

  normalizes :instance_host, with: ->(host) { host.strip.downcase }
  validates :instance_host, presence: true, length: { maximum: 253 }
  validates :redirect_uri, presence: true
  validates :client_credentials, presence: true, if: :stored?
  validates :client_credentials, absence: true, if: :operator_config?
end
