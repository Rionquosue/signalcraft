# frozen_string_literal: true

require "pathname"

# Framework-independent core of SignalCraft. Everything under lib/signal_craft
# loads without Rails so it can be tested and used at container start-up.
module SignalCraft
  # Version of the addon (plugin) API this host implements; see
  # design specifications/04_Rails_Plugin_API_Specification.md.
  PLUGIN_API_VERSION = "1.2.0"

  # Deployment layout: the application lives at /var/www/signalcraft, with the
  # operator-provided plugins/ and config/ directories beneath it. In
  # development the repository root plays the same role.
  DEFAULT_ROOT = "/var/www/signalcraft"

  class << self
    def root
      @root ||= Pathname.new(ENV.fetch("SIGNALCRAFT_ROOT") { File.expand_path("..", __dir__) })
    end

    def config_dir
      root.join("config")
    end

    def plugins_dir
      root.join("plugins")
    end

    # Loaded once during boot (config/application.rb) and frozen afterwards.
    def settings
      @settings or raise "SignalCraft.settings used before SignalCraft.load_settings!"
    end

    def settings_loaded?
      !@settings.nil?
    end

    def load_settings!(env: ENV)
      require_relative "signal_craft/settings"
      @settings = Settings.load(config_dir: config_dir, env: env)
    end

    def reset_settings!
      @settings = nil
    end
  end
end
