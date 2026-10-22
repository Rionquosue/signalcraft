# frozen_string_literal: true

class User < ApplicationRecord
  # bcrypt with the configured cost; passwords over 72 bytes are rejected by
  # has_secure_password's validations (design specifications/02, Credential storage).
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, length: { in: 3..320 },
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { case_sensitive: false }
  validates :display_name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :timezone, presence: true

  scope :active, -> { where(disabled_at: nil) }

  def disabled?
    disabled_at.present?
  end

  # Re-hashes with the current cost after a successful login when the stored
  # hash is weaker than the current configuration. Called with the password
  # the user just entered; it is never stored or logged.
  def rehash_password_if_needed!(plain_password)
    stored = BCrypt::Password.new(password_digest)
    target_cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
    return false if stored.cost >= target_cost

    update!(password: plain_password)
    true
  end

  def membership_in(workspace)
    memberships.find_by(workspace: workspace)
  end
end
