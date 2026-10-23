# frozen_string_literal: true

require "test_helper"

# The content hash covers exactly what the provider receives (design specifications/04, TargetSnapshot).
class SnapshotTest < ActiveSupport::TestCase
  setup do
    @target = post_targets(:launch_bluesky)
  end

  test "equal content hashes equally regardless of option key order" do
    @target.provider_options = { "b" => 1, "a" => { "y" => 2, "x" => 3 } }
    _, first = Publishing::Snapshot.build(@target)
    @target.provider_options = { "a" => { "x" => 3, "y" => 2 }, "b" => 1 }
    _, second = Publishing::Snapshot.build(@target)

    assert_equal first, second
  end

  test "the platform's own text changes the hash; the revision alone does not" do
    snapshot, original = Publishing::Snapshot.build(@target)
    assert_equal posts(:launch).body, snapshot["text"]

    @target.revision += 1
    assert_equal original, Publishing::Snapshot.build(@target).last

    @target.body_override = "Shorter copy"
    snapshot, changed = Publishing::Snapshot.build(@target)
    assert_equal "Shorter copy", snapshot["text"]
    assert_not_equal original, changed
  end

  test "the addon receives a frozen DTO" do
    dto = Publishing::Snapshot.to_dto(Publishing::Snapshot.build(@target).first)
    assert dto.frozen?
    assert_equal @target.id, dto.target_id
  end
end
