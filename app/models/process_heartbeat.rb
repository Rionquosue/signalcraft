# frozen_string_literal: true

class ProcessHeartbeat < ApplicationRecord
  self.primary_key = "process_key"

  string_enum :role, %w[web media worker]

  def self.beat!(role:, process_key: "#{Socket.gethostname}:#{Process.pid}")
    upsert({ process_key: process_key, role: role, hostname: Socket.gethostname,
             release: ENV.fetch("SIGNALCRAFT_RELEASE", "development"),
             started_at: PROCESS_STARTED_AT, last_seen_at: Time.current }, unique_by: :process_key)
  end

  PROCESS_STARTED_AT = Time.current
end
