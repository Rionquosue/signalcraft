# frozen_string_literal: true

# Append-only audit log (design specifications/08). Rows are never updated;
# the runtime database role cannot delete them.
class AuditEvent < ApplicationRecord
  string_enum :actor_type, %w[user system plugin]

  def readonly?
    persisted?
  end

  def self.record!(action:, actor: Current.user, workspace: nil, subject: nil, details: nil)
    create!(
      action: action,
      actor_type: actor ? "user" : "system",
      actor_user_id: actor&.id,
      actor_label: actor&.display_name || "system",
      workspace_id: workspace&.id,
      subject_type: subject&.class&.name,
      subject_id: subject&.id,
      details: details,
      request_id: Current.request_id,
      ip_address: Current.ip_address
    )
  end
end
