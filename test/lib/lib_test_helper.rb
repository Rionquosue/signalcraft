# frozen_string_literal: true

# Helper for tests of lib/signal_craft, which must work without Rails.
# Run one file:   ruby -Ilib -Itest test/lib/settings_test.rb
# Run them all:   bin/rails test test/lib   (or: rake test:lib)
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "signal_craft"

module LibTestHelper
  def with_tmpdir
    Dir.mktmpdir("signalcraft-test") { |dir| yield Pathname(dir) }
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end
end
