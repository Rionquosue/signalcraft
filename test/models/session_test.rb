# frozen_string_literal: true

require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "stores only a digest of the token" do
    session, token = Session.start!(user: users(:alice))
    assert_equal Digest::SHA256.digest(token), session.token_digest
    assert_not_equal token, session.token_digest
  end

  test "finds a live session by its token" do
    session, token = Session.start!(user: users(:alice))
    assert_equal session, Session.find_by_token(token)
    assert_nil Session.find_by_token("not-a-token")
    assert_nil Session.find_by_token(nil)
  end

  test "expired and idle sessions are not found" do
    session, token = Session.start!(user: users(:alice))
    session.update_columns(expires_at: 1.minute.ago)
    assert_nil Session.find_by_token(token)

    session.update_columns(expires_at: 1.day.from_now, last_seen_at: 15.days.ago)
    assert_nil Session.find_by_token(token)
  end

  test "sessions of disabled users are not found" do
    _session, token = Session.start!(user: users(:disabled))
    assert_nil Session.find_by_token(token)
  end
end
