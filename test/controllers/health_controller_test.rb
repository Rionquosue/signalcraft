# frozen_string_literal: true

require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "live and ready respond without authentication" do
    get "/health/live"
    assert_response :success
    assert_equal "ok", response.body

    get "/health/ready"
    assert_response :success
    assert_equal "ready", response.body
  end
end
