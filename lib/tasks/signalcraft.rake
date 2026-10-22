# frozen_string_literal: true

namespace :signalcraft do
  namespace :plugins do
    desc "Record addons from the plugins directory in the database"
    task sync: :environment do
      result = PluginRegistrySync.call
      puts "Addons loaded: #{result.loaded.join(', ').presence || 'none'}"
      puts "Addons failed: #{result.failed.join(', ')}" if result.failed.any?
      puts "Addons missing: #{result.missing.join(', ')}" if result.missing.any?
    end

    desc "Write plugins/.lock.json (run at image build)"
    task :lock do
      require_relative "../signal_craft"
      require_relative "../signal_craft/plugins/lock"
      SignalCraft::Plugins::Lock.write(SignalCraft.plugins_dir)
      puts "Wrote #{SignalCraft.plugins_dir.join(SignalCraft::Plugins::Lock::FILE)}"
    end
  end

  desc "Validate operator configuration and print it with secrets redacted"
  task :check_config do
    require_relative "../signal_craft"
    settings = SignalCraft.load_settings!
    settings.to_h.each { |key, value| puts "#{key}: #{value.inspect}" }
  end
end

namespace :test do
  desc "Run framework-independent tests in test/lib"
  task :lib do
    files = Dir[File.expand_path("../../test/lib/**/*_test.rb", __dir__)]
    ruby "-Ilib -Itest -e 'ARGV.each { |f| require f }' #{files.join(' ')}"
  end
end
