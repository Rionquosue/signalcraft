# frozen_string_literal: true

class UploadSession < ApplicationRecord
  belongs_to :workspace
  belongs_to :media_asset
  belongs_to :user

  scope :in_progress, -> { where(completed_at: nil).where("expires_at > ?", Time.current) }
end
