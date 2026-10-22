# frozen_string_literal: true

require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  test "the last owner cannot be demoted or removed" do
    owner = memberships(:alice_studio)
    assert_not owner.update(role: "editor")
    assert_not owner.destroy
    assert Membership.exists?(owner.id)
  end

  test "an owner can be demoted when another owner exists" do
    memberships(:bob_studio).update!(role: "owner")
    assert memberships(:alice_studio).update(role: "editor")
  end
end
