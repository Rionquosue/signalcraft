require_relative "boot"

require "rails"
# Frameworks in use. Active Storage, Action Cable, Action Text and Action
# Mailbox are deliberately left out: media lives in PostgreSQL chunks through a
# custom repository (design specifications/02), and live updates use polling.
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Framework-independent core (lib/signal_craft). Loaded explicitly, not
# autoloaded, because settings are needed before Rails configures itself.
require_relative "../lib/signal_craft"
require_relative "../lib/signal_craft/settings"
require_relative "../lib/signal_craft/plugins/registry"
require_relative "../lib/signal_craft/plugins/lock"

# Operator configuration from config/signalcraft.yml, the environment and
# secret files. An invalid configuration stops boot with every problem listed.
SignalCraft.load_settings!

module SignalCraft
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    settings = SignalCraft.settings

    # Times are stored in UTC; display time zones come from each user,
    # workspace or account (design specifications/02, Scheduling semantics).
    config.time_zone = "UTC"

    # The schema uses partial and expression indexes, deferrable constraints,
    # generated columns and a trigger, which schema.rb cannot represent.
    config.active_record.schema_format = :sql

    config.secret_key_base = settings.secret_key_base

    # Active Record Encryption for provider credentials, checkpoints and other
    # secrets (design specifications/02, Credential storage). Keys come from
    # secret files, never from the database or the image.
    config.active_record.encryption.primary_key = settings.encryption_primary_keys
    config.active_record.encryption.key_derivation_salt = settings.encryption_key_derivation_salt
    config.active_record.encryption.store_key_references = true
    config.active_record.encryption.support_unencrypted_data = false

    # Solid Queue in the application database; retries are declared per job
    # with retry_on / discard_on.
    config.active_job.queue_adapter = :solid_queue

    # Accept requests only for the configured public host.
    config.hosts << URI(settings.public_base_url).host
    config.host_authorization = { exclude: ->(request) { request.path.start_with?("/health/") } }

    config.generators.system_tests = nil
  end
end
