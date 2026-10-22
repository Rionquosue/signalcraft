# frozen_string_literal: true

class Membership < ApplicationRecord
  ROLES = %w[owner editor viewer].freeze

  belongs_to :workspace
  belongs_to :user

  string_enum :role, ROLES

  validates :user_id, uniqueness: { scope: :workspace_id }
  validate :workspace_keeps_an_owner, on: :update, if: :will_save_change_to_role?
  before_destroy :ensure_not_last_owner

  def can_publish?
    owner? || editor?
  end

  private

  def other_owners_exist?
    Membership.owner.where(workspace_id: workspace_id).where.not(id: id).exists?
  end

  def workspace_keeps_an_owner
    return unless role_was == "owner" && !owner?

    errors.add(:role, "cannot be changed: a workspace needs at least one owner") unless other_owners_exist?
  end

  def ensure_not_last_owner
    return unless owner? && !other_owners_exist?

    errors.add(:base, "A workspace needs at least one owner")
    throw :abort
  end
end
