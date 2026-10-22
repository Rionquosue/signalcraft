# frozen_string_literal: true

# pg_dump 17 and later write `SET transaction_timeout = 0;` into
# db/structure.sql. PostgreSQL 16 and older reject that setting, so a dump
# made with a newer client than the server cannot be loaded back (for
# example into test databases). The setting only affects the restore session,
# so it is removed after every dump to keep structure.sql portable across the
# supported servers (PostgreSQL 13 or later).
Rake::Task["db:schema:dump"].enhance do
  path = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
  )
  if path && File.exist?(path)
    sql = File.read(path)
    cleaned = sql.gsub(/^SET transaction_timeout = .*;\n/, "")
    File.write(path, cleaned) unless cleaned == sql
  end
end
