# frozen_string_literal: true

class PostTargetMedia < ApplicationRecord
  self.table_name = "post_target_media"

  belongs_to :post_target, inverse_of: :post_target_media
  belongs_to :media_asset

  validates :position, inclusion: { in: 0..19 }
  validates :alt_text, length: { maximum: 5000 }
end
