# Password hashing (design specifications/02, Credential storage).
#
# Rails 8.1's has_secure_password supports bcrypt only, so the specification's
# fallback applies: bcrypt at the configured cost (default 12), with the
# 72-byte limit enforced by has_secure_password's validations. Argon2id
# becomes available through `has_secure_password algorithm: :argon2` in a
# later Rails release; User#rehash_password_if_needed upgrades hashes at login.
require "bcrypt"

settings = SignalCraft.settings
if settings.password_hash_algorithm != "bcrypt"
  raise SignalCraft::Settings::Error,
        "password_hash_algorithm #{settings.password_hash_algorithm} is not supported by this Rails version; use bcrypt"
end

BCrypt::Engine.cost = settings.bcrypt_cost unless Rails.env.test?
