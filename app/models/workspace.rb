# frozen_string_literal: true

class Workspace < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_many :workspace_plugins, dependent: :destroy
  has_many :social_accounts, dependent: :restrict_with_error
  has_many :posts, dependent: :restrict_with_error
  has_many :post_targets, dependent: :restrict_with_error
  has_many :media_assets, dependent: :restrict_with_error

  attribute :media_quota_bytes, :integer, default: -> { SignalCraft.settings.workspace_media_quota_bytes }
  attribute :default_timezone, :string, default: -> { SignalCraft.settings.default_timezone }

  validates :name, presence: true, length: { maximum: 100 }
  validates :media_quota_bytes, numericality: { only_integer: true, greater_than: 0 }
  validates :reporting_currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :attribution_window_days, numericality: { in: 1..30 }
  validates_known_time_zone :default_timezone

  scope :active, -> { where(archived_at: nil) }

  def owners
    users.merge(Membership.owner)
  end
end
