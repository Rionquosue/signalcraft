# frozen_string_literal: true

# A stored file, original or variant, held in PostgreSQL chunks
# (design specifications/02, PostgreSQL media storage; 07 for protection).
class MediaAsset < ApplicationRecord
  STATES = %w[uploading uploaded validating ready rejected failed expired].freeze

  belongs_to :workspace
  belongs_to :source_asset, class_name: "MediaAsset", optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :protection_declared_by, class_name: "User", optional: true
  has_many :variants, class_name: "MediaAsset", foreign_key: :source_asset_id, dependent: :restrict_with_error,
                      inverse_of: :source_asset
  has_many :media_chunks, -> { order(:seq) }, dependent: :delete_all
  has_one :upload_session, dependent: :destroy

  string_enum :kind, %w[original variant]
  string_enum :state, STATES
  string_enum :media_kind, %w[image video audio], prefix: :media, validate: { allow_nil: true }

  validates :byte_size, numericality: { only_integer: true, in: 1..268_435_456 }
  validates :original_filename, length: { maximum: 255 }

  # The author's statement that this image was protected against AI training
  # before upload (design specifications/07). Refused for video, for variants,
  # and while variants exist (the database enforces the same rules).
  def declare_protection!(by:, tool: nil)
    raise ArgumentError, "only original images can be declared protected" unless original? && (media_kind.nil? || media_image?)
    raise ArgumentError, "remove this image's adjusted copies first" if variants.exists?

    update!(protection_declared: true, protection_tool: tool.presence, protection_declared_by: by,
            protection_declared_at: Time.current)
  end

  def withdraw_protection!
    update!(protection_declared: false, protection_tool: nil, protection_declared_by: nil, protection_declared_at: nil)
  end
end
