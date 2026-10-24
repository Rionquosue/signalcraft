# frozen_string_literal: true

# A rate limit an addon reported, persisted at the scope it applies to
# (design specifications/04, Independent schedules and provider limits):
# one account, the whole provider, or this deployment's API client
# (provider_app, keyed by plugin_app_registration id).
class ProviderThrottle < ApplicationRecord
  SCOPES = %w[account provider provider_app].freeze

  belongs_to :plugin

  string_enum :scope, SCOPES, prefix: true

  # Latest retry time among the throttles that apply to an account, if any is still in force.
  def self.blocking_until(account, now: Time.current)
    applicable = scope_keys(account).map { |scope, key| where(scope: scope, scope_key: key) }.reduce(:or)
    where(plugin_id: account.plugin_id).and(applicable).where("retry_at > ?", now).maximum(:retry_at)
  end

  def self.record!(account, scope:, retry_at:, now: Time.current)
    upsert({ plugin_id: account.plugin_id, scope: scope, scope_key: scope_keys(account).fetch(scope),
             retry_at: retry_at, updated_at: now },
           unique_by: %i[plugin_id scope scope_key])
  end

  # The scope_key each scope uses for an account.
  def self.scope_keys(account)
    { "account" => account.id.to_s, "provider" => "", "provider_app" => account.plugin_app_registration_id.to_s }
  end
  private_class_method :scope_keys
end
