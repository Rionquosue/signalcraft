# frozen_string_literal: true

class MediaChunk < ApplicationRecord
  self.primary_key = %i[media_asset_id seq]

  belongs_to :media_asset
end
