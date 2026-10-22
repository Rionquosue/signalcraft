# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "manifest"

module SignalCraft
  module Plugins
    # Discovers addons in the plugins directory (/var/www/signalcraft/plugins
    # in a deployment). Each addon is one subdirectory holding a Ruby gem:
    #
    #   plugins/
    #     bluesky/
    #       signalcraft_plugin.yml   manifest (sheet 04)
    #       bluesky.gemspec          gem loaded by the Gemfile at image build
    #       lib/...
    #
    # Discovery never loads addon code; it only reads manifests. Code is
    # loaded by Bundler from the Gemfile, which was resolved when the image was
    # built, so nothing is installed at runtime (sheet 04, Scope and trust).
    class Registry
      MANIFEST_FILE = "signalcraft_plugin.yml"
      MAX_MANIFEST_BYTES = 64 * 1024

      Entry = Struct.new(:directory, :id, :manifest, :errors, keyword_init: true) do
        def loaded?
          errors.empty?
        end

        def status
          loaded? ? "loaded" : "failed"
        end
      end

      attr_reader :directory, :entries

      def self.scan(directory = SignalCraft.plugins_dir, host_api_version: SignalCraft::PLUGIN_API_VERSION)
        new(directory, host_api_version).tap(&:scan)
      end

      def initialize(directory, host_api_version)
        @directory = Pathname(directory)
        @host_api_version = host_api_version
        @entries = []
      end

      def scan
        @entries = plugin_directories.map { |dir| read_entry(dir) }
        mark_duplicates
        @entries.freeze
        self
      end

      def loaded
        entries.select(&:loaded?)
      end

      def failed
        entries.reject(&:loaded?)
      end

      def find(id)
        loaded.find { |entry| entry.id == id }
      end

      # Gemspecs the Gemfile should load; one per addon directory.
      def self.gemspecs(directory = SignalCraft.plugins_dir)
        Pathname(directory).glob("*/*.gemspec").sort
      end

      private

      def plugin_directories
        return [] unless directory.directory?

        directory.children.select(&:directory?).reject { |dir| dir.basename.to_s.start_with?(".") }.sort
      end

      def read_entry(dir)
        errors = []
        manifest_path = dir.join(MANIFEST_FILE)
        manifest = nil

        if !manifest_path.file?
          errors << "#{MANIFEST_FILE} is missing"
        elsif manifest_path.size > MAX_MANIFEST_BYTES
          errors << "#{MANIFEST_FILE} is larger than #{MAX_MANIFEST_BYTES} bytes"
        else
          begin
            data = YAML.safe_load(manifest_path.read, permitted_classes: [], aliases: false)
            manifest = Manifest.build(data, host_api_version: @host_api_version)
          rescue Psych::Exception => e
            errors << "#{MANIFEST_FILE} is not valid YAML (#{e.message.lines.first&.strip})"
          rescue Manifest::Invalid => e
            errors.concat(e.errors)
          end
        end

        gemspecs = dir.glob("*.gemspec")
        errors << "expected exactly one .gemspec, found #{gemspecs.size}" unless gemspecs.size == 1

        id = manifest&.id
        if manifest && id != dir.basename.to_s
          errors << "directory name '#{dir.basename}' must match the addon id '#{id}'"
        end

        Entry.new(directory: dir, id: id || dir.basename.to_s, manifest: manifest, errors: errors)
      end

      def mark_duplicates
        @entries.group_by(&:id).each do |id, group|
          next if group.size < 2

          group.each { |entry| entry.errors << "duplicate addon id '#{id}'" }
        end
      end
    end
  end
end
