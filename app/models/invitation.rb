# frozen_string_literal: true

class Invitation < ApplicationRecord
  include DigestedToken

  LIFETIME = 7.days

  belongs_to :workspace
  belongs_to :inviter, class_name: "User", foreign_key: :invited_by, optional: true
  belongs_to :accepter, class_name: "User", foreign_key: :accepted_by, optional: true

  string_enum :role, Membership::ROLES

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at > ?", Time.current) }

  # Returns [invitation, token]; only the digest is stored.
  def self.issue!(workspace:, email:, role:, invited_by:)
    token = generate_token
    invitation = create!(workspace: workspace, email: email, role: role, inviter: invited_by,
                         token_digest: digest(token), expires_at: LIFETIME.from_now)
    [invitation, token]
  end

  def self.find_open_by_token(token)
    return nil if token.blank?

    pending.find_by(token_digest: digest(token))
  end
end
