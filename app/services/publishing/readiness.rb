# frozen_string_literal: true

module Publishing
  # Rechecked at claim time and again just before sending: account
  # connection, addon availability and media (design specifications/02,
  # Publishing state and delivery; 04, Normalized errors).
  module Readiness
    CONNECTION_BLOCKS = {
      "disconnected" => "account_disconnected",
      "reauthorization_required" => "reauthorization_required",
      "plugin_unavailable" => "plugin_unavailable"
    }.freeze

    module_function

    # A blocked_reason for the target, or nil when it can be sent.
    def blocked_reason(target)
      account = target.social_account
      plugin = account.plugin
      return CONNECTION_BLOCKS[account.connection_status] if CONNECTION_BLOCKS.key?(account.connection_status)
      return "plugin_unavailable" unless plugin.usable? && Addons.publisher_for(plugin)
      return "plugin_disabled" unless WorkspacePlugin.enabled.exists?(workspace_id: target.workspace_id,
                                                                      plugin_id: plugin.plugin_id)
      return "validation_failed" if target.scheduling_problem

      # Media preparation (prepare_media, provider variants and signed
      # fetches) is not built yet, so posts with media cannot be sent.
      return "media_unavailable" if target.effective_media.any?

      nil
    end
  end
end
