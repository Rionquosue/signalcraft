# frozen_string_literal: true

module Publishing
  # Finds the social publisher for an installed addon. Entrypoints come only
  # from the plugins table, which is written from validated manifests at
  # deployment (PluginRegistrySync), never from user input
  # (design specifications/04, Manifest and discovery).
  module Addons
    module_function

    def publisher_for(plugin)
      return nil unless plugin&.usable? && plugin.social?

      entrypoint = plugin.manifest["entrypoint"].to_s
      return nil unless entrypoint.match?(SignalCraft::Plugins::Manifest::CONSTANT_PATTERN)

      entrypoint.safe_constantize&.new
    end

    def capability?(plugin, name)
      plugin.manifest.dig("capabilities", name.to_s) == true
    end
  end
end
