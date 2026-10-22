# frozen_string_literal: true

# Records the addons found in the plugins directory in the `plugins` table
# (design specifications/04, Manifest and discovery; 08, plugins).
#
# - A valid manifest is stored with load_status "loaded" (or "failed" when its
#   gem code does not define the declared entrypoint).
# - An invalid one is stored as "failed" with the reasons, so owners see it.
# - Addons that disappeared are kept as "missing" so history still refers to them.
#
# Runs on every deployment from the migrate role (bin/docker-entrypoint).
class PluginRegistrySync
  Result = Struct.new(:loaded, :failed, :missing, keyword_init: true)

  def self.call(registry: SignalCraft::Plugins::Registry.scan(SignalCraft.plugins_dir), now: Time.current)
    new(registry, now).call
  end

  def initialize(registry, now)
    @registry = registry
    @now = now
  end

  def call
    seen = []
    result = Result.new(loaded: [], failed: [], missing: [])

    Plugin.transaction do
      @registry.entries.each do |entry|
        next if entry.manifest.nil? # nothing reliable to record without a valid id

        errors = entry.errors + entrypoint_errors(entry)
        upsert(entry.manifest, errors)
        seen << entry.id
        (errors.empty? ? result.loaded : result.failed) << entry.id
      end

      missing = Plugin.where.not(plugin_id: seen).where.not(load_status: "missing")
      result.missing.concat(missing.pluck(:plugin_id))
      missing.update_all(load_status: "missing", load_error: "Addon directory not found in this release",
                         updated_at: @now)
    end

    unrecorded = @registry.entries.select { |entry| entry.manifest.nil? }
    unrecorded.each do |entry|
      Rails.logger.warn("[plugins] #{entry.directory.basename} not recorded: #{entry.errors.join('; ')}")
    end
    result
  end

  private

  def entrypoint_errors(entry)
    return [] unless entry.loaded?

    constant = entry.manifest.entrypoint.safe_constantize
    constant ? [] : ["entrypoint #{entry.manifest.entrypoint} is not defined by the addon's code"]
  end

  def upsert(manifest, errors)
    plugin = Plugin.find_or_initialize_by(plugin_id: manifest.id)
    plugin.assign_attributes(
      kind: manifest.kind,
      version: manifest.version.to_s,
      plugin_api: manifest.plugin_api.to_s,
      manifest: manifest.to_h,
      load_status: errors.empty? ? "loaded" : "failed",
      load_error: errors.empty? ? nil : errors.join("; ").first(2000),
      last_seen_at: @now
    )
    plugin.save!
  end
end
