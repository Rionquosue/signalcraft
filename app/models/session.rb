# frozen_string_literal: true

# A signed-in browser. The cookie holds a random token; only its SHA-256
# digest is stored (design specifications/02, Lookup tokens).
class Session < ApplicationRecord
  ABSOLUTE_LIFETIME = 30.days
  IDLE_TIMEOUT = 14.days
  TOUCH_INTERVAL = 5.minutes

  belongs_to :user

  scope :live, -> { where("expires_at > ? AND last_seen_at > ?", Time.current, IDLE_TIMEOUT.ago) }

  # Returns [session, token]. The token is shown to the browser once.
  def self.start!(user:, ip_address: nil, user_agent: nil)
    token = SecureRandom.urlsafe_base64(32)
    session = create!(
      user: user,
      token_digest: digest(token),
      ip_address: ip_address,
      user_agent: user_agent.to_s.first(512).presence,
      last_seen_at: Time.current,
      expires_at: ABSOLUTE_LIFETIME.from_now
    )
    [session, token]
  end

  def self.find_by_token(token)
    return nil if token.blank? || token.length > 200

    session = live.includes(:user).find_by(token_digest: digest(token))
    return nil if session.nil? || session.user.disabled?

    session.touch_last_seen
    session
  end

  def self.digest(token)
    Digest::SHA256.digest(token)
  end

  def touch_last_seen
    update_column(:last_seen_at, Time.current) if last_seen_at < TOUCH_INTERVAL.ago
  end
end
