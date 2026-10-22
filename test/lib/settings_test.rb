# frozen_string_literal: true

require_relative "lib_test_helper"
require "signal_craft/settings"

class SettingsTest < Minitest::Test
  include LibTestHelper

  def secret_files(dir)
    {
      "DATABASE_PASSWORD_FILE" => write(dir.join("secrets/db"), "pg-password\n").to_s,
      "SECRET_KEY_BASE_FILE" => write(dir.join("secrets/skb"), "a" * 64).to_s,
      "ENCRYPTION_PRIMARY_KEYS_FILE" => write(dir.join("secrets/keys"), "#{'k' * 32}\n#{'n' * 32}\n").to_s,
      "ENCRYPTION_KEY_DERIVATION_SALT_FILE" => write(dir.join("secrets/salt"), "s" * 32).to_s
    }
  end

  def minimal_env(dir)
    secret_files(dir).merge(
      "PUBLIC_BASE_URL" => "https://social.example.org/",
      "DATABASE_HOST" => "postgres",
      "DATABASE_NAME" => "signalcraft",
      "DATABASE_USER" => "signalcraft_app",
      "DATABASE_SSLMODE" => "disable",
      "WORKSPACE_MEDIA_QUOTA_BYTES" => "10737418240"
    )
  end

  def test_loads_minimal_configuration_with_defaults
    with_tmpdir do |dir|
      settings = SignalCraft::Settings.load(config_dir: dir, env: minimal_env(dir))

      assert_equal "https://social.example.org", settings.public_base_url, "trailing slash removed"
      assert_equal 5432, settings.database_port
      assert_equal "pg-password", settings.database_password, "trailing newline removed from secret file"
      assert_equal ["k" * 32, "n" * 32], settings.encryption_primary_keys
      assert_equal 12, settings.bcrypt_cost
      assert_equal "America/Toronto", settings.default_timezone
      assert_equal 2_097_152, settings.media_chunk_bytes
      assert settings.values.frozen?
    end
  end

  def test_yaml_file_is_read_and_environment_wins
    with_tmpdir do |dir|
      write(dir.join("signalcraft.yml"), <<~YAML)
        database_port: 6543
        rails_max_threads: 5
        default_timezone: Europe/Paris
      YAML
      env = minimal_env(dir).merge("RAILS_MAX_THREADS" => "7")
      settings = SignalCraft::Settings.load(config_dir: dir, env: env)

      assert_equal 6543, settings.database_port
      assert_equal 7, settings.rails_max_threads
      assert_equal "Europe/Paris", settings.default_timezone
    end
  end

  def test_secret_file_paths_in_yaml_are_relative_to_config_dir
    with_tmpdir do |dir|
      write(dir.join("secrets/db_from_yaml"), "from-yaml")
      write(dir.join("signalcraft.yml"), "database_password_file: secrets/db_from_yaml\n")
      env = minimal_env(dir).except("DATABASE_PASSWORD_FILE")

      assert_equal "from-yaml", SignalCraft::Settings.load(config_dir: dir, env: env).database_password
    end
  end

  def test_reports_every_missing_required_setting_at_once
    with_tmpdir do |dir|
      error = assert_raises(SignalCraft::Settings::Error) do
        SignalCraft::Settings.load(config_dir: dir, env: {})
      end

      %w[public_base_url database_host database_sslmode secret_key_base
         encryption_primary_keys workspace_media_quota_bytes].each do |key|
        assert_includes error.message, "#{key} is required"
      end
    end
  end

  def test_rejects_inline_secrets
    with_tmpdir do |dir|
      env = minimal_env(dir).merge("DATABASE_PASSWORD" => "plain")
      error = assert_raises(SignalCraft::Settings::Error) { SignalCraft::Settings.load(config_dir: dir, env: env) }
      assert_includes error.message, "must be supplied as a file"

      write(dir.join("signalcraft.yml"), "secret_key_base: inline\n")
      error = assert_raises(SignalCraft::Settings::Error) do
        SignalCraft::Settings.load(config_dir: dir, env: minimal_env(dir))
      end
      assert_includes error.message, "secret_key_base is a secret"
    end
  end

  def test_rejects_missing_secret_file
    with_tmpdir do |dir|
      env = minimal_env(dir).merge("DATABASE_PASSWORD_FILE" => dir.join("nope").to_s)
      error = assert_raises(SignalCraft::Settings::Error) { SignalCraft::Settings.load(config_dir: dir, env: env) }
      assert_includes error.message, "missing or unreadable"
    end
  end

  def test_validates_types_ranges_and_urls
    with_tmpdir do |dir|
      env = minimal_env(dir).merge(
        "PUBLIC_BASE_URL" => "http://insecure.example.org",
        "DATABASE_SSLMODE" => "sometimes",
        "MEDIA_CHUNK_BYTES" => "100",
        "DATABASE_PORT" => "five",
        "DEFAULT_TIMEZONE" => "not a zone"
      )
      error = assert_raises(SignalCraft::Settings::Error) { SignalCraft::Settings.load(config_dir: dir, env: env) }

      assert_includes error.message, "public_base_url must use https"
      assert_includes error.message, "database_sslmode must be one of"
      assert_includes error.message, "media_chunk_bytes must be between"
      assert_includes error.message, "database_port must be a valid integer"
      assert_includes error.message, "default_timezone must be an IANA time zone"
    end
  end

  def test_rejects_short_secrets
    with_tmpdir do |dir|
      env = minimal_env(dir).merge("SECRET_KEY_BASE_FILE" => write(dir.join("short"), "abc").to_s)
      error = assert_raises(SignalCraft::Settings::Error) { SignalCraft::Settings.load(config_dir: dir, env: env) }
      assert_includes error.message, "secret_key_base must be at least 64 characters"
      refute_includes error.message, "abc", "secret values never appear in errors"
    end
  end

  def test_unknown_yaml_keys_and_invalid_yaml_are_errors
    with_tmpdir do |dir|
      write(dir.join("signalcraft.yml"), "databse_host: typo\n")
      error = assert_raises(SignalCraft::Settings::Error) do
        SignalCraft::Settings.load(config_dir: dir, env: minimal_env(dir))
      end
      assert_includes error.message, "unknown setting 'databse_host'"

      write(dir.join("signalcraft.yml"), "a: [unclosed\n")
      error = assert_raises(SignalCraft::Settings::Error) do
        SignalCraft::Settings.load(config_dir: dir, env: minimal_env(dir))
      end
      assert_includes error.message, "not valid YAML"
    end
  end

  def test_provider_budgets_in_micro_dollars
    with_tmpdir do |dir|
      settings = SignalCraft::Settings.load(config_dir: dir, env: minimal_env(dir).merge("PROVIDER_BUDGETS" => "x=25.50"))
      assert_equal({ "x" => 25_500_000 }, settings.provider_budgets)

      error = assert_raises(SignalCraft::Settings::Error) do
        SignalCraft::Settings.load(config_dir: dir, env: minimal_env(dir).merge("PROVIDER_BUDGETS" => "X!=5"))
      end
      assert_includes error.message, "is not a plugin id"
    end
  end

  def test_redacted_hash_hides_secrets
    with_tmpdir do |dir|
      hash = SignalCraft::Settings.load(config_dir: dir, env: minimal_env(dir)).to_h

      assert_equal "[REDACTED]", hash[:database_password]
      assert_equal "[REDACTED]", hash[:secret_key_base]
      assert_nil hash[:ffmpeg_api_key], "absent optional secrets stay nil"
      assert_equal "postgres", hash[:database_host]
    end
  end
end
