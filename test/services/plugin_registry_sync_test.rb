# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SyncTestAddon
  class Adapter; end
end

class PluginRegistrySyncTest < ActiveSupport::TestCase
  def manifest(id, entrypoint)
    <<~YAML
      id: #{id}
      kind: social
      name: #{id.titleize}
      version: 1.2.3
      plugin_api: ">=1.2 <2.0"
      entrypoint: #{entrypoint}
      capabilities:
        text: true
    YAML
  end

  def with_plugins(definitions)
    Dir.mktmpdir do |dir|
      definitions.each do |id, content|
        FileUtils.mkdir_p(File.join(dir, id))
        File.write(File.join(dir, id, "signalcraft_plugin.yml"), content)
        File.write(File.join(dir, id, "#{id}.gemspec"), "# test\n")
      end
      yield SignalCraft::Plugins::Registry.scan(dir)
    end
  end

  test "records loaded, failed and missing addons" do
    with_plugins(
      "sync_test" => manifest("sync_test", "SyncTestAddon::Adapter"),
      "no_code" => manifest("no_code", "NoSuchAddon::Adapter")
    ) do |registry|
      result = PluginRegistrySync.call(registry: registry)

      assert_equal %w[sync_test], result.loaded
      assert_equal %w[no_code], result.failed
      assert_includes result.missing, "bluesky", "fixture addon is not in this directory"

      loaded = Plugin.find("sync_test")
      assert loaded.status_loaded?
      assert_equal "1.2.3", loaded.version
      assert_equal true, loaded.manifest.dig("capabilities", "text")

      failed = Plugin.find("no_code")
      assert failed.status_failed?
      assert_includes failed.load_error, "NoSuchAddon::Adapter is not defined"

      assert Plugin.find("bluesky").status_missing?
    end
  end

  test "invalid manifests are logged, not recorded" do
    with_plugins("broken" => "id: [nope\n") do |registry|
      assert_no_difference -> { Plugin.count } do
        PluginRegistrySync.call(registry: registry)
      end
    end
  end
end
