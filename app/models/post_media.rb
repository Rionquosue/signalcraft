# frozen_string_literal: true

class PostMedia < ApplicationRecord
  self.table_name = "post_media"

  belongs_to :post, inverse_of: :post_media
  belongs_to :media_asset

  validates :position, inclusion: { in: 0..19 }
  validates :alt_text, length: { maximum: 5000 }
end
