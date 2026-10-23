# frozen_string_literal: true

# A connected social account. Credentials are encrypted and only decrypted
# inside the addon call that needs them (design specifications/02, Credential storage).
class SocialAccount < ApplicationRecord
  CONNECTION_STATUSES = %w[connected reauthorization_required disconnected plugin_unavailable].freeze

  belongs_to :workspace
  belongs_to :plugin, foreign_key: :plugin_id, primary_key: :plugin_id, inverse_of: :social_accounts
  belongs_to :plugin_app_registration
  belongs_to :connector, class_name: "User", foreign_key: :connected_by, optional: true
  has_one :channel_queue, dependent: :destroy
  has_many :post_targets, dependent: :restrict_with_error

  string_enum :connection_status, CONNECTION_STATUSES
  encrypts :credentials

  validates :provider_account_id, presence: true, length: { maximum: 255 },
                                  uniqueness: { scope: %i[workspace_id plugin_app_registration_id] }
  validates :display_name, presence: true, length: { maximum: 255 }
  validates :credentials, presence: true, if: :connected?

  # Every account has a queue, so its posting times can be set right away.
  after_create { ChannelQueue.for_account!(self) }

  def timezone
    channel_queue&.timezone || workspace.default_timezone
  end
end
