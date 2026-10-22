# frozen_string_literal: true

require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  test "records an event and cannot be changed afterwards" do
    event = AuditEvent.record!(action: "test.happened", actor: users(:alice), workspace: workspaces(:studio),
                               details: { "field" => "value" })
    assert_equal "user", event.actor_type
    assert_equal "Alice Owner", event.actor_label
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(action: "changed") }
  end
end
