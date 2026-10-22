# frozen_string_literal: true

require "rubygems"

module SignalCraft
  module Plugins
    # A validated addon manifest (design specifications/04, Manifest and
    # discovery). Validation is strict: unknown keys are errors, so a typo in
    # a capability cannot silently become "false".
    class Manifest
      class Invalid < StandardError
        attr_reader :errors

        def initialize(errors)
          @errors = errors.freeze
          super(errors.join("; "))
        end
      end

      ID_PATTERN = /\A[a-z][a-z0-9_]{0,63}\z/
      CONSTANT_PATTERN = /\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/
      SETTING_KEY_PATTERN = /\A[a-z][a-z0-9_]{0,63}\z/

      KINDS = %w[social commerce].freeze
      AUTH_STRATEGIES = %w[oauth2 oauth2_pkce atproto_oauth api_key app_password relay_token].freeze
      LINK_PLACEMENTS = %w[in_post profile_only none].freeze
      METRIC_KEYS = %w[
        views impressions reach likes replies reposts quotes shares saves
        link_clicks avg_watch_seconds total_watch_seconds
      ].freeze
      ATTRIBUTION_CODE_KINDS = %w[none discount affiliate].freeze
      SETTING_TYPES = %w[boolean enum string integer decimal secret].freeze
      DYNAMIC_VALUE_SOURCES = %w[creator_info].freeze

      TOP_LEVEL_KEYS = %w[
        id kind name version plugin_api entrypoint config_schema_version
        checkpoint_schema_version auth capabilities settings hosts
      ].freeze
      REQUIRED_KEYS = %w[id kind name version plugin_api entrypoint].freeze

      # capability => [type, extra]
      SOCIAL_CAPABILITIES = {
        "text" => :boolean, "images" => :boolean, "video" => :boolean, "audio" => :boolean,
        "alt_text" => :boolean, "requires_media" => :boolean, "media_fetch_by_url" => :boolean,
        "remote_idempotency" => :boolean, "reconciliation" => :boolean, "webhooks" => :boolean,
        "delete_remote" => :boolean, "link_placement" => :link_placement, "metrics" => :metrics,
        "metrics_max_age_days" => :positive_integer
      }.freeze
      COMMERCE_CAPABILITIES = {
        "webhooks" => :boolean, "refunds_visible" => :boolean, "fees_reported" => :boolean,
        "attribution_codes" => :attribution_codes, "order_history_days" => :optional_positive_integer
      }.freeze
      SOCIAL_DEFAULTS = SOCIAL_CAPABILITIES.to_h do |key, type|
        [key, { boolean: false, link_placement: "none", metrics: [], positive_integer: nil }.fetch(type)]
      end.freeze
      COMMERCE_DEFAULTS = {
        "webhooks" => false, "refunds_visible" => false, "fees_reported" => false,
        "attribution_codes" => "none", "order_history_days" => nil
      }.freeze

      attr_reader :id, :kind, :name, :version, :plugin_api, :entrypoint, :config_schema_version,
                  :checkpoint_schema_version, :auth, :capabilities, :settings, :hosts, :raw

      # Parses and validates. Raises Invalid with every problem found.
      def self.build(data, host_api_version: SignalCraft::PLUGIN_API_VERSION)
        errors = []
        manifest = new(data, host_api_version, errors)
        raise Invalid, errors unless errors.empty?

        manifest
      end

      def social?
        kind == "social"
      end

      def commerce?
        kind == "commerce"
      end

      def to_h
        {
          "id" => id, "kind" => kind, "name" => name, "version" => version.to_s,
          "plugin_api" => plugin_api.to_s, "entrypoint" => entrypoint,
          "config_schema_version" => config_schema_version,
          "checkpoint_schema_version" => checkpoint_schema_version,
          "auth" => auth, "capabilities" => capabilities, "settings" => settings, "hosts" => hosts
        }
      end

      private

      def initialize(data, host_api_version, errors)
        @errors = errors
        unless data.is_a?(Hash)
          errors << "manifest must be a mapping"
          return
        end

        @raw = data
        data = data.transform_keys(&:to_s)
        (data.keys - TOP_LEVEL_KEYS).each { |key| errors << "unknown manifest field '#{key}'" }
        REQUIRED_KEYS.each { |key| errors << "missing required field '#{key}'" if blank?(data[key]) }

        @id = string_field(data, "id", pattern: ID_PATTERN, message: "must match [a-z][a-z0-9_]{0,63}")
        @kind = enum_field(data, "kind", KINDS)
        @name = string_field(data, "name", max: 100)
        @version = version_field(data["version"])
        @plugin_api = api_requirement(data["plugin_api"], host_api_version)
        @entrypoint = string_field(data, "entrypoint", pattern: CONSTANT_PATTERN,
                                                       message: "must be a Ruby constant name")
        @config_schema_version = schema_version(data, "config_schema_version")
        @checkpoint_schema_version = schema_version(data, "checkpoint_schema_version")
        @auth = auth_field(data["auth"])
        @capabilities = capabilities_field(data["capabilities"])
        @settings = settings_field(data["settings"])
        @hosts = hosts_field(data["hosts"])
        freeze
      end

      def string_field(data, key, pattern: nil, message: nil, max: 255)
        value = data[key]
        return nil if value.nil?

        unless value.is_a?(String) && !value.empty? && value.length <= max
          @errors << "'#{key}' must be a non-empty string of at most #{max} characters"
          return nil
        end
        @errors << "'#{key}' #{message}" if pattern && !value.match?(pattern)
        value.dup.freeze
      end

      def enum_field(data, key, allowed)
        value = data[key]
        return nil if value.nil?

        @errors << "'#{key}' must be one of #{allowed.join(', ')}" unless allowed.include?(value)
        value
      end

      def version_field(value)
        return nil if value.nil?

        Gem::Version.new(value.to_s)
      rescue ArgumentError
        @errors << "'version' must be a version number such as 1.0.0"
        nil
      end

      # Accepts ">=1.2 <2.0" or ">=1.2, <2.0".
      def api_requirement(value, host_api_version)
        return nil if value.nil?

        parts = value.to_s.split(/[\s,]+/).reject(&:empty?)
        parts = parts.each_with_object([]) do |part, acc|
          # Re-join operators separated from versions by a space (">= 1.2").
          if acc.last&.match?(/\A(>=|<=|~>|=|!=|>|<)\z/)
            acc[-1] = "#{acc.last} #{part}"
          else
            acc << part
          end
        end
        requirement = Gem::Requirement.new(*parts)
        unless requirement.satisfied_by?(Gem::Version.new(host_api_version))
          @errors << "'plugin_api' #{value} is not compatible with this host's addon API #{host_api_version}"
        end
        requirement
      rescue Gem::Requirement::BadRequirementError, ArgumentError
        @errors << "'plugin_api' must be a version requirement such as \">=1.2 <2.0\""
        nil
      end

      def schema_version(data, key)
        value = data.fetch(key, 1)
        return value if value.is_a?(Integer) && value.positive?

        @errors << "'#{key}' must be a positive integer"
        1
      end

      def auth_field(value)
        return {} if value.nil?
        return invalid("'auth' must be a mapping", {}) unless value.is_a?(Hash)

        value = value.transform_keys(&:to_s)
        (value.keys - %w[strategy scopes]).each { |key| @errors << "unknown auth field '#{key}'" }
        strategy = value["strategy"]
        unless AUTH_STRATEGIES.include?(strategy)
          @errors << "'auth.strategy' must be one of #{AUTH_STRATEGIES.join(', ')}"
        end
        scopes = value.fetch("scopes", [])
        unless scopes.is_a?(Array) && scopes.all? { |s| s.is_a?(String) && !s.empty? && s.length <= 255 }
          @errors << "'auth.scopes' must be a list of strings"
          scopes = []
        end
        { "strategy" => strategy, "scopes" => scopes.uniq }.freeze
      end

      def capabilities_field(value)
        schema, defaults =
          case kind
          when "social" then [SOCIAL_CAPABILITIES, SOCIAL_DEFAULTS]
          when "commerce" then [COMMERCE_CAPABILITIES, COMMERCE_DEFAULTS]
          else return {}
          end
        return defaults if value.nil?
        return invalid("'capabilities' must be a mapping", defaults) unless value.is_a?(Hash)

        value = value.transform_keys(&:to_s)
        result = defaults.dup
        value.each do |key, item|
          type = schema[key]
          if type.nil?
            @errors << "unknown #{kind} capability '#{key}'"
            next
          end
          result[key] = capability_value(key, type, item)
        end
        result.freeze
      end

      def capability_value(key, type, item)
        case type
        when :boolean
          return item if [true, false].include?(item)

          invalid("capability '#{key}' must be true or false", false)
        when :link_placement
          return item if LINK_PLACEMENTS.include?(item)

          invalid("capability 'link_placement' must be one of #{LINK_PLACEMENTS.join(', ')}", "none")
        when :metrics
          unless item.is_a?(Array) && (item - METRIC_KEYS).empty? && item.uniq.size == item.size
            return invalid("capability 'metrics' must list distinct keys from: #{METRIC_KEYS.join(', ')}", [])
          end

          item.freeze
        when :attribution_codes
          return item if ATTRIBUTION_CODE_KINDS.include?(item)

          invalid("capability 'attribution_codes' must be one of #{ATTRIBUTION_CODE_KINDS.join(', ')}", "none")
        when :positive_integer
          return item if item.is_a?(Integer) && item.positive?

          invalid("capability '#{key}' must be a positive integer", nil)
        when :optional_positive_integer
          return item if item.nil? || (item.is_a?(Integer) && item.positive?)

          invalid("capability '#{key}' must be a positive integer or null", nil)
        end
      end

      def settings_field(value)
        return [].freeze if value.nil?
        return invalid("'settings' must be a list", [].freeze) unless value.is_a?(Array)

        keys = []
        value.each_with_index.map do |item, index|
          label = "settings[#{index}]"
          unless item.is_a?(Hash)
            @errors << "#{label} must be a mapping"
            next
          end
          item = item.transform_keys(&:to_s)
          (item.keys - %w[key type values values_from default label help]).each do |unknown|
            @errors << "#{label}: unknown field '#{unknown}'"
          end
          key = item["key"]
          @errors << "#{label}: 'key' must match [a-z][a-z0-9_]*" unless key.is_a?(String) && key.match?(SETTING_KEY_PATTERN)
          @errors << "#{label}: duplicate key '#{key}'" if keys.include?(key)
          keys << key
          type = item["type"]
          @errors << "#{label}: 'type' must be one of #{SETTING_TYPES.join(', ')}" unless SETTING_TYPES.include?(type)
          validate_setting_values(label, item)
          @errors << "#{label}: secret settings cannot have a default" if type == "secret" && item.key?("default")
          item.freeze
        end.compact.freeze
      end

      def validate_setting_values(label, item)
        if item["type"] == "enum"
          values = item["values"]
          dynamic = item["values_from"]
          if dynamic
            @errors << "#{label}: 'values_from' must be one of #{DYNAMIC_VALUE_SOURCES.join(', ')}" unless DYNAMIC_VALUE_SOURCES.include?(dynamic)
          elsif !(values.is_a?(Array) && !values.empty? && values.all? { |v| v.is_a?(String) })
            @errors << "#{label}: enum settings need a non-empty 'values' list or 'values_from'"
          elsif item.key?("default") && !values.include?(item["default"])
            @errors << "#{label}: default must be one of its values"
          end
        elsif item.key?("values") || item.key?("values_from")
          @errors << "#{label}: only enum settings take 'values'"
        end
      end

      def hosts_field(value)
        return [].freeze if value.nil?
        unless value.is_a?(Array) && value.all? { |h| h.is_a?(String) && h.match?(/\A[a-z0-9*.-]+\z/) }
          return invalid("'hosts' must be a list of lower-case host names", [].freeze)
        end

        value.uniq.freeze
      end

      def invalid(message, fallback)
        @errors << message
        fallback
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
