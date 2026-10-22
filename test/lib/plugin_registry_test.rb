# frozen_string_literal: true

require_relative "lib_test_helper"
require "signal_craft/plugins/registry"
require "signal_craft/plugins/lock"

class PluginRegistryTest < Minitest::Test
  include LibTestHelper

  MANIFEST = <<~YAML
    id: %<id>s
    kind: social
    name: Example
    version: 1.0.0
    plugin_api: ">=1.2 <2.0"
    entrypoint: Example::Adapter
  YAML

  def add_plugin(root, dir_name, id: dir_name, gemspec: true, manifest: nil)
    write(root.join(dir_name, "signalcraft_plugin.yml"), manifest || format(MANIFEST, id: id))
    write(root.join(dir_name, "#{dir_name}.gemspec"), "# gemspec\n") if gemspec
  end

  def test_missing_directory_yields_no_entries
    with_tmpdir do |dir|
      assert_empty SignalCraft::Plugins::Registry.scan(dir.join("absent")).entries
    end
  end

  def test_loads_valid_plugins_and_ignores_hidden_directories
    with_tmpdir do |dir|
      add_plugin(dir, "alpha_social")
      add_plugin(dir, "beta_social")
      FileUtils.mkdir_p(dir.join(".git"))
      registry = SignalCraft::Plugins::Registry.scan(dir)

      assert_equal %w[alpha_social beta_social], registry.loaded.map(&:id)
      assert_empty registry.failed
      assert_equal "Example", registry.find("beta_social").manifest.name
    end
  end

  def test_reports_failures_without_raising
    with_tmpdir do |dir|
      add_plugin(dir, "no_gemspec", gemspec: false)
      add_plugin(dir, "wrong_dir", id: "other_name")
      add_plugin(dir, "bad_yaml", manifest: "id: [oops\n")
      FileUtils.mkdir_p(dir.join("empty_dir"))
      registry = SignalCraft::Plugins::Registry.scan(dir)

      failures = registry.failed.to_h { |entry| [entry.directory.basename.to_s, entry.errors] }
      assert_includes failures["no_gemspec"], "expected exactly one .gemspec, found 0"
      assert_includes failures["wrong_dir"], "directory name 'wrong_dir' must match the addon id 'other_name'"
      assert(failures["bad_yaml"].any? { |e| e.include?("not valid YAML") })
      assert_includes failures["empty_dir"], "signalcraft_plugin.yml is missing"
      assert_empty registry.loaded
    end
  end

  def test_yaml_aliases_and_objects_are_refused
    with_tmpdir do |dir|
      add_plugin(dir, "aliased", manifest: "base: &b {a: 1}\nid: aliased\nother: *b\n")
      add_plugin(dir, "objecty", manifest: "id: !ruby/object:OpenStruct {}\n")
      registry = SignalCraft::Plugins::Registry.scan(dir)

      assert_equal 2, registry.failed.size
      registry.failed.each { |entry| assert(entry.errors.any? { |e| e.include?("not valid YAML") }) }
    end
  end

  def test_lock_detects_changes
    with_tmpdir do |dir|
      add_plugin(dir, "alpha_social")
      SignalCraft::Plugins::Lock.write(dir)
      assert SignalCraft::Plugins::Lock.verify!(dir)

      write(dir.join("alpha_social", "lib", "injected.rb"), "puts :hi")
      error = assert_raises(SignalCraft::Plugins::Lock::Mismatch) { SignalCraft::Plugins::Lock.verify!(dir) }
      assert_includes error.message, "alpha_social/lib/injected.rb"
    end
  end

  def test_lock_missing_is_a_mismatch
    with_tmpdir do |dir|
      assert_raises(SignalCraft::Plugins::Lock::Mismatch) { SignalCraft::Plugins::Lock.verify!(dir) }
    end
  end
end
