# frozen_string_literal: true

# Failed-login counters shared by every web process (design specifications/02,
# Security and operations). Keys are keyed hashes of the e-mail address or IP
# address, so the table does not reveal who tried to sign in.
class LoginThrottle < ApplicationRecord
  self.primary_key = "key_digest"

  WINDOW = 15.minutes
  LOCK_DURATION = 15.minutes
  LIMITS = { "email" => 10, "ip" => 50 }.freeze

  string_enum :scope, LIMITS.keys

  def self.key_for(scope, value)
    secret = Rails.application.key_generator.generate_key("signalcraft login throttle", 32)
    OpenSSL::HMAC.digest("SHA256", secret, "#{scope}:#{value.to_s.downcase.strip}")
  end

  def self.locked?(email:, ip_address:)
    keys = { "email" => email, "ip" => ip_address }.filter_map { |scope, value| key_for(scope, value) if value.present? }
    where(key_digest: keys).where("locked_until > ?", Time.current).exists?
  end

  def self.record_failure!(email:, ip_address:)
    { "email" => email, "ip" => ip_address }.each do |scope, value|
      bump!(scope, value) if value.present?
    end
  end

  def self.reset!(email:)
    where(key_digest: key_for("email", email)).delete_all
  end

  # One row per key, created on first failure and locked while it is updated,
  # so concurrent failed logins cannot lose counts.
  def self.bump!(scope, value)
    key = key_for(scope, value)
    transaction do
      row = create_or_find_by!(key_digest: key) do |new_row|
        new_row.scope = scope
        new_row.window_started_at = Time.current
        new_row.attempt_count = 0
      end
      row.lock!

      if row.window_started_at < WINDOW.ago
        row.window_started_at = Time.current
        row.attempt_count = 0
      end
      row.attempt_count += 1
      row.locked_until = LOCK_DURATION.from_now if row.attempt_count >= LIMITS.fetch(scope)
      row.updated_at = Time.current
      row.save!
    end
  end
  private_class_method :bump!
end
