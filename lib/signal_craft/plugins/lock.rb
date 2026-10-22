# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module SignalCraft
  module Plugins
    # Fingerprint of the plugins directory, written when the image is built
    # (bin/plugin-lock) and checked at container start (bin/docker-entrypoint).
    #
    # The plugins directory may be mounted from the host so operators can see
    # what is installed, but addon code is only ever loaded from what Bundler
    # resolved at build time. If the mounted directory no longer matches the
    # build, the container refuses to start instead of running code that was
    # never reviewed or bundled (sheet 04, Scope and trust).
    class Lock
      FILE = ".lock.json"
      VERSION = 1

      class Mismatch < StandardError; end

      def self.fingerprint(directory)
        directory = Pathname(directory)
        files = directory.directory? ? directory.glob("**/*", File::FNM_DOTMATCH).select(&:file?) : []
        files = files.reject { |path| path.basename.to_s == FILE }
        entries = files.map do |path|
          [path.relative_path_from(directory).to_s, Digest::SHA256.file(path).hexdigest]
        end.sort
        { "version" => VERSION, "files" => entries.to_h }
      end

      def self.write(directory)
        directory = Pathname(directory)
        directory.mkpath
        directory.join(FILE).write(JSON.pretty_generate(fingerprint(directory)) + "\n")
      end

      def self.verify!(directory)
        directory = Pathname(directory)
        lock_path = directory.join(FILE)
        raise Mismatch, "#{lock_path} is missing; rebuild the image after changing plugins" unless lock_path.file?

        expected = JSON.parse(lock_path.read)
        actual = fingerprint(directory)
        return true if expected == actual

        expected_files = expected.fetch("files", {}).to_a
        actual_files = actual["files"].to_a
        changed = ((expected_files - actual_files) | (actual_files - expected_files)).map(&:first).uniq.sort
        raise Mismatch, "plugins directory differs from the image build (#{changed.first(10).join(', ')}); " \
                        "rebuild the image to install or change addons"
      rescue JSON::ParserError
        raise Mismatch, "#{lock_path} is not valid JSON"
      end
    end
  end
end
