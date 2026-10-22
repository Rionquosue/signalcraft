# frozen_string_literal: true

# /health/live: the process is up. /health/ready: the database is reachable
# and fully migrated (design specifications/02, Configuration and capacity).
# No secrets or paths are ever returned.
class HealthController < ActionController::Base
  def live
    render plain: "ok"
  end

  def ready
    ActiveRecord::Base.with_connection { |connection| connection.select_value("SELECT 1") }
    if ActiveRecord::Base.connection_pool.migration_context.needs_migration?
      render plain: "pending migrations", status: :service_unavailable
    else
      render plain: "ready"
    end
  rescue ActiveRecord::ActiveRecordError, PG::Error
    render plain: "database unavailable", status: :service_unavailable
  end
end
