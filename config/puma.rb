require_relative "../lib/signal_craft"
require_relative "../lib/signal_craft/settings"
SignalCraft.load_settings! unless SignalCraft.settings_loaded?

# Puma for the web role: UI, authentication, OAuth callbacks, webhooks.
# The media role uses config/puma_media.rb (design specifications/02).
settings = SignalCraft.settings

threads_count = settings.rails_max_threads
threads threads_count, threads_count
workers settings.web_concurrency if settings.web_concurrency > 1

port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
