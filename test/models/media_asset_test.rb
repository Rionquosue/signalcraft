# frozen_string_literal: true

require "test_helper"

# Declared protection (design specifications/07).
class MediaAssetTest < ActiveSupport::TestCase
  def create_original(**attributes)
    MediaAsset.create!({ workspace: workspaces(:studio), kind: "original", state: "uploaded", byte_size: 1000,
                         sha256: SecureRandom.bytes(32), media_kind: "image" }.merge(attributes))
  end

  test "an image can be declared protected" do
    asset = create_original
    asset.declare_protection!(by: users(:alice), tool: "Nightshade")
    assert asset.reload.protection_declared
    assert_equal "Nightshade", asset.protection_tool
  end

  test "video cannot be declared protected" do
    asset = create_original(media_kind: "video")
    assert_raises(ArgumentError) { asset.declare_protection!(by: users(:alice)) }
  end

  test "the database refuses variants of a protected image" do
    asset = create_original
    asset.declare_protection!(by: users(:alice))

    assert_raises(ActiveRecord::InvalidForeignKey) do
      MediaAsset.create!(workspace: workspaces(:studio), kind: "variant", source_asset: asset,
                         source_protection_declared: false, variant_key: "resize:1080",
                         state: "uploading", byte_size: 10)
    end
  end
end
