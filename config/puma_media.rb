# Puma for the media role: chunked uploads, range previews and signed media
# fetches, kept apart so slow media clients cannot starve the UI
# (design specifications/02, Image and process model).
require_relative "../lib/signal_craft"
require_relative "../lib/signal_craft/settings"
SignalCraft.load_settings! unless SignalCraft.settings_loaded?

threads_count = Integer(ENV.fetch("MEDIA_MAX_THREADS", 5))
threads threads_count, threads_count

port ENV.fetch("PORT", 3001)

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
