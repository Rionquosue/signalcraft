# Addon discovery (design specifications/04). Manifests in the plugins
# directory are validated at boot; problems are logged and shown to owners,
# and never stop the application. Records in the `plugins` table are synced
# by `bin/rails signalcraft:plugins:sync`, which the migrate role runs on
# each deployment (bin/docker-entrypoint).
Rails.application.config.after_initialize do
  registry = SignalCraft::Plugins::Registry.scan(SignalCraft.plugins_dir)
  Rails.application.config.x.plugin_registry = registry

  registry.failed.each do |entry|
    Rails.logger.warn("[plugins] #{entry.directory.basename}: #{entry.errors.join('; ')}")
  end
end
