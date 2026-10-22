# frozen_string_literal: true

require "pathname"
require "uri"
require "yaml"

module SignalCraft
  # Operator configuration for one deployment.
  #
  # Sources, lowest precedence first:
  #   1. built-in defaults below;
  #   2. config/signalcraft.yml (lower-case keys);
  #   3. environment variables (upper-case keys).
  #
  # Secrets are never written inline. They are read from files named by
  # `<key>_file` in the YAML file or `<KEY>_FILE` in the environment, which
  # is how Docker secrets and read-only secret mounts under config/secrets/
  # are supplied (design specifications/02, Configuration and capacity and
  # Credential storage).
  #
  # Every problem is collected and reported together, and an invalid
  # configuration stops the process before it serves anything.
  class Settings
    class Error < StandardError; end

    CONFIG_FILE = "signalcraft.yml"
    MAX_CONFIG_BYTES = 256 * 1024
    MAX_SECRET_BYTES = 64 * 1024

    SSL_MODES = %w[disable allow prefer require verify-ca verify-full].freeze
    PASSWORD_ALGORITHMS = %w[bcrypt argon2id].freeze

    Definition = Struct.new(:key, :type, :default, :required, :secret, :options, keyword_init: true)

    def self.define(key, type, default: nil, required: false, secret: false, **options)
      (@definitions ||= {})[key] = Definition.new(
        key: key, type: type, default: default, required: required, secret: secret, options: options
      )
    end

    def self.definitions
      @definitions
    end

    # --- Public origin -------------------------------------------------------
    define :public_base_url, :url, required: true, https: true
    define :public_media_base_url, :url, https: true

    # --- Existing PostgreSQL ---------------------------------------------------
    define :database_host, :string, required: true
    define :database_port, :integer, default: 5432, min: 1, max: 65_535
    define :database_name, :string, required: true
    define :database_user, :string, required: true
    # Optional: local servers may use trust or peer authentication.
    define :database_password, :string, secret: true
    define :database_sslmode, :enum, required: true, values: SSL_MODES
    define :database_pool, :integer, default: 5, min: 1, max: 100

    # --- Application secrets ---------------------------------------------------
    define :secret_key_base, :string, required: true, secret: true, min_length: 64
    # Several primary keys may be supplied (one per line) during key rotation;
    # Rails encrypts with the last and decrypts with any.
    define :encryption_primary_keys, :list, required: true, secret: true, min_length: 32
    define :encryption_key_derivation_salt, :string, required: true, secret: true, min_length: 32

    # --- Passwords (02, Credential storage) -----------------------------------
    define :password_hash_algorithm, :enum, default: "bcrypt", values: PASSWORD_ALGORITHMS
    define :bcrypt_cost, :integer, default: 12, min: 10, max: 16

    # --- FFmpeg service (01, 03) -------------------------------------------------
    define :ffmpeg_base_url, :url, default: "http://ffmpeg:8080"
    define :ffmpeg_api_key, :string, secret: true

    # --- Capacity ------------------------------------------------------------------
    define :web_concurrency, :integer, default: 1, min: 1, max: 32
    define :rails_max_threads, :integer, default: 3, min: 1, max: 64
    define :publish_concurrency, :integer, default: 2, min: 1, max: 32

    # --- Media -----------------------------------------------------------------------
    define :max_upload_bytes, :integer, default: 268_435_456, min: 1, max: 268_435_456
    define :media_chunk_bytes, :integer, default: 2_097_152, min: 262_144, max: 8_388_608
    define :max_uploads_per_user, :integer, default: 2, min: 1, max: 20
    define :max_range_response_bytes, :integer, default: 8_388_608, min: 65_536, max: 67_108_864
    define :workspace_media_quota_bytes, :integer, required: true, min: 1

    # --- Scheduling (02, Lateness and missed schedules) ------------------------------
    define :dispatch_interval_seconds, :integer, default: 15, min: 1, max: 300
    define :missed_schedule_grace_seconds, :integer, default: 900, min: 0, max: 86_400
    define :provider_pending_timeout_seconds, :integer, default: 3600, min: 60, max: 604_800
    define :default_timezone, :timezone, default: "America/Toronto"

    # --- Providers ------------------------------------------------------------------------
    # Monthly spend limit in US dollars per paid provider, e.g. { "x" => 25 }.
    define :provider_budgets, :budget_map, default: {}

    attr_reader :values

    def self.load(config_dir:, env: ENV)
      new(config_dir: Pathname(config_dir), env: env).tap(&:validate!)
    end

    def initialize(config_dir:, env:)
      @config_dir = config_dir
      @env = env
      @errors = []
      @values = {}
      file_values = read_config_file
      self.class.definitions.each_value do |definition|
        @values[definition.key] = resolve(definition, file_values)
      end
      @values.freeze
    end

    def validate!
      return self if @errors.empty?

      raise Error, "Invalid SignalCraft configuration:\n" + @errors.map { |e| "  - #{e}" }.join("\n")
    end

    def [](key)
      @values.fetch(key.to_sym)
    end

    def respond_to_missing?(name, include_private = false)
      @values.key?(name) || super
    end

    def method_missing(name, *args)
      return @values.fetch(name) if args.empty? && @values.key?(name)

      super
    end

    # Values safe to log or show to an owner: secrets are replaced.
    def to_h(redacted: true)
      @values.to_h do |key, value|
        secret = self.class.definitions.fetch(key).secret
        [key, redacted && secret && !value.nil? ? "[REDACTED]" : value]
      end
    end

    def tracked_links_possible?
      !self[:public_base_url].nil?
    end

    private

    def read_config_file
      path = @config_dir.join(CONFIG_FILE)
      return {} unless path.file?

      if path.size > MAX_CONFIG_BYTES
        @errors << "#{CONFIG_FILE} is larger than #{MAX_CONFIG_BYTES} bytes"
        return {}
      end

      data = YAML.safe_load(path.read, permitted_classes: [], aliases: false) || {}
      unless data.is_a?(Hash)
        @errors << "#{CONFIG_FILE} must contain a mapping of settings"
        return {}
      end

      known = self.class.definitions.keys.flat_map { |k| [k.to_s, "#{k}_file"] }
      (data.keys.map(&:to_s) - known).each { |unknown| @errors << "#{CONFIG_FILE}: unknown setting '#{unknown}'" }
      data.transform_keys(&:to_s)
    rescue Psych::Exception => e
      @errors << "#{CONFIG_FILE} is not valid YAML (#{e.message.lines.first&.strip})"
      {}
    end

    def resolve(definition, file_values)
      key = definition.key.to_s
      env_key = key.upcase

      raw, source =
        if definition.secret
          resolve_secret(definition, file_values)
        elsif @env.key?(env_key)
          [@env[env_key], "environment variable #{env_key}"]
        elsif file_values.key?(key)
          [file_values[key], "#{CONFIG_FILE} '#{key}'"]
        else
          [nil, nil]
        end

      if blank?(raw)
        @errors << "#{key} is required (#{hint_for(definition)})" if definition.required
        return definition.default
      end

      coerce(definition, raw, source)
    end

    def resolve_secret(definition, file_values)
      key = definition.key.to_s
      env_key = key.upcase

      if @env.key?(env_key) || file_values.key?(key)
        @errors << "#{key} is a secret and must be supplied as a file (#{env_key}_FILE or #{key}_file), " \
                   "not as a plain value"
        return [nil, nil]
      end

      path_value, source =
        if @env.key?("#{env_key}_FILE")
          [@env["#{env_key}_FILE"], "#{env_key}_FILE"]
        elsif file_values.key?("#{key}_file")
          [file_values["#{key}_file"], "#{CONFIG_FILE} '#{key}_file'"]
        end
      return [nil, nil] if blank?(path_value)

      path = Pathname(path_value.to_s)
      path = @config_dir.join(path) if path.relative?
      unless path.file? && path.readable?
        @errors << "#{key}: secret file named by #{source} is missing or unreadable"
        return [nil, nil]
      end
      if path.size > MAX_SECRET_BYTES
        @errors << "#{key}: secret file named by #{source} is too large"
        return [nil, nil]
      end

      [path.read.chomp, "secret file named by #{source}"]
    end

    def coerce(definition, raw, source)
      opts = definition.options
      key = definition.key

      case definition.type
      when :string
        value = raw.to_s
        check_min_length(key, value, opts)
        value
      when :integer
        value = Integer(raw.to_s, 10)
        if (opts[:min] && value < opts[:min]) || (opts[:max] && value > opts[:max])
          @errors << "#{key} must be between #{opts[:min]} and #{opts[:max]} (from #{source})"
        end
        value
      when :enum
        value = raw.to_s
        unless opts[:values].include?(value)
          @errors << "#{key} must be one of #{opts[:values].join(', ')} (from #{source})"
        end
        value
      when :url
        coerce_url(key, raw.to_s, opts, source)
      when :list
        values = raw.is_a?(Array) ? raw.map(&:to_s) : raw.to_s.split(/[\n,]/)
        values = values.map(&:strip).reject(&:empty?)
        @errors << "#{key} must contain at least one value (from #{source})" if values.empty?
        values.each { |v| check_min_length(key, v, opts) }
        values.freeze
      when :timezone
        value = raw.to_s
        unless value.match?(%r{\A[A-Za-z][A-Za-z0-9_+\-]*(/[A-Za-z0-9_+\-]+)*\z})
          @errors << "#{key} must be an IANA time zone name such as America/Toronto (from #{source})"
        end
        value
      when :budget_map
        coerce_budget_map(key, raw, source)
      else
        raise ArgumentError, "unknown setting type #{definition.type}"
      end
    rescue ArgumentError, TypeError
      @errors << "#{key} must be a valid #{definition.type} (from #{source})"
      definition.default
    end

    def coerce_url(key, value, opts, source)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
        @errors << "#{key} must be an absolute http(s) URL (from #{source})"
        return value
      end
      @errors << "#{key} must use https (from #{source})" if opts[:https] && uri.scheme != "https"
      if uri.user || uri.password || uri.query || uri.fragment
        @errors << "#{key} must not contain credentials, a query or a fragment (from #{source})"
      end
      value.chomp("/").freeze
    rescue URI::InvalidURIError
      @errors << "#{key} is not a valid URL (from #{source})"
      value
    end

    def coerce_budget_map(key, raw, source)
      hash =
        case raw
        when Hash then raw
        when String
          raw.split(",").to_h do |pair|
            plugin, amount = pair.split("=", 2).map(&:strip)
            raise ArgumentError if plugin.nil? || amount.nil?

            [plugin, amount]
          end
        else raise ArgumentError
        end

      hash.to_h do |plugin, amount|
        plugin = plugin.to_s
        unless plugin.match?(/\A[a-z][a-z0-9_]{0,63}\z/)
          @errors << "#{key}: '#{plugin}' is not a plugin id (from #{source})"
        end
        dollars = Float(amount.to_s)
        @errors << "#{key}: budget for #{plugin} must not be negative (from #{source})" if dollars.negative?
        [plugin, (dollars * 1_000_000).round] # stored in micro-dollars
      end.freeze
    end

    def check_min_length(key, value, opts)
      return unless opts[:min_length] && value.length < opts[:min_length]

      @errors << "#{key} must be at least #{opts[:min_length]} characters"
    end

    def hint_for(definition)
      key = definition.key.to_s
      if definition.secret
        "set #{key.upcase}_FILE or #{key}_file in #{CONFIG_FILE}"
      else
        "set #{key.upcase} or #{key} in #{CONFIG_FILE}"
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
