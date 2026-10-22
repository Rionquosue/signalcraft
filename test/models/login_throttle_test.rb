# frozen_string_literal: true

require "test_helper"

class LoginThrottleTest < ActiveSupport::TestCase
  test "locks an e-mail address after repeated failures and resets on success" do
    9.times { LoginThrottle.record_failure!(email: "alice@example.com", ip_address: "192.0.2.1") }
    assert_not LoginThrottle.locked?(email: "alice@example.com", ip_address: "192.0.2.1")

    LoginThrottle.record_failure!(email: "alice@example.com", ip_address: "192.0.2.1")
    assert LoginThrottle.locked?(email: "alice@example.com", ip_address: "192.0.2.99")

    LoginThrottle.reset!(email: "alice@example.com")
    assert_not LoginThrottle.locked?(email: "alice@example.com", ip_address: "192.0.2.99")
  end

  test "stores keyed hashes, not addresses" do
    LoginThrottle.record_failure!(email: "alice@example.com", ip_address: "192.0.2.1")
    LoginThrottle.pluck(:key_digest).each do |digest|
      assert_equal 32, digest.bytesize
      assert_not_includes digest, "alice"
    end
  end
end
