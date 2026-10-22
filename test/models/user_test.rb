# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes e-mail addresses" do
    user = User.new(email: "  New.Person@Example.COM ", display_name: "New", password: PASSWORD)
    assert_equal "new.person@example.com", user.email
  end

  test "requires a password of at least 12 characters" do
    user = User.new(email: "short@example.com", display_name: "Short", password: "short")
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 12 characters)"
  end

  test "rejects passwords longer than bcrypt's 72-byte limit" do
    user = User.new(email: "long@example.com", display_name: "Long", password: "a" * 73)
    assert_not user.valid?
    assert user.errors[:password].any?
  end

  test "authenticates by e-mail and password, ignoring case" do
    assert_equal users(:alice), User.authenticate_by(email: "ALICE@example.com", password: PASSWORD)
    assert_nil User.authenticate_by(email: "alice@example.com", password: "wrong password!!")
  end

  test "stores only a salted bcrypt hash" do
    user = User.create!(email: "hash@example.com", display_name: "Hash", password: PASSWORD)
    assert_match(/\A\$2a\$\d\d\$/, user.password_digest)
    assert_not_includes user.password_digest, PASSWORD
  end

  test "the database refuses a password_digest that is not a hash" do
    assert_raises(ActiveRecord::StatementInvalid) do
      users(:alice).update_column(:password_digest, "plaintext")
    end
  end

  test "rehashes a weaker hash at login" do
    user = users(:alice) # fixture hash uses bcrypt's minimum cost
    min_cost = ActiveModel::SecurePassword.min_cost
    ActiveModel::SecurePassword.min_cost = false
    BCrypt::Engine.stub(:cost, 10) do
      assert user.rehash_password_if_needed!(PASSWORD)
      assert_not user.reload.rehash_password_if_needed!(PASSWORD), "already at the current cost"
    end
    assert_equal 10, BCrypt::Password.new(user.reload.password_digest).cost
  ensure
    ActiveModel::SecurePassword.min_cost = min_cost
  end
end
