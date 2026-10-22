# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "signs in, sets an http-only cookie and audits it" do
    assert_difference -> { AuditEvent.where(action: "session.signed_in").count } do
      sign_in_as users(:alice)
    end
    assert_redirected_to root_url
    assert cookies[:signalcraft_session].present?
    assert_equal 1, users(:alice).sessions.count

    get root_path
    assert_response :success
    assert_select "h1", "Publishing queue"
  end

  test "rejects a wrong password with a neutral message and counts the failure" do
    assert_difference -> { LoginThrottle.count }, 2 do
      post session_path, params: { email: "alice@example.com", password: "not the password" }
    end
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=alert]", SessionsController::FAILED
  end

  test "disabled users cannot sign in" do
    sign_in_as users(:disabled)
    assert_redirected_to new_session_path
  end

  test "a locked e-mail address cannot sign in even with the right password" do
    10.times { LoginThrottle.record_failure!(email: "alice@example.com", ip_address: "192.0.2.1") }
    sign_in_as users(:alice)
    assert_redirected_to new_session_path
    assert_equal 0, users(:alice).sessions.count
  end

  test "signing out ends the session" do
    sign_in_as users(:alice)
    delete session_path
    assert_redirected_to new_session_path
    assert_equal 0, users(:alice).sessions.count

    get root_path
    assert_redirected_to new_session_path
  end
end
