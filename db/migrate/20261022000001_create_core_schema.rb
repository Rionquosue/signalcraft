# frozen_string_literal: true

# Creates every application table defined in design specifications/08.
# The SQL is kept as a file so it can be compared byte-for-byte with the
# specification's reference DDL (bin/check-schema-sync).
class CreateCoreSchema < ActiveRecord::Migration[8.1]
  SQL_FILE = Rails.root.join("db/sql/0001_core_schema.sql")

  def up
    execute SQL_FILE.read
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "drop the database instead; this is the initial schema"
  end
end
