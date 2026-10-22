# frozen_string_literal: true

require "test_helper"

# Every string enum must list exactly the values its column's CHECK
# constraint allows (design specifications/08), so the model and the database
# can never disagree about a state or reason.
class EnumConsistencyTest < ActiveSupport::TestCase
  MODELS = [
    Membership, Invitation, Plugin, PluginAppRegistration, SocialAccount, PostTarget, MediaAsset,
    PublishIntent, PublishAttempt, AuditEvent, LoginThrottle, ProcessHeartbeat
  ].freeze

  def check_values(table, column)
    definitions = ActiveRecord::Base.with_connection do |connection|
      connection.select_values(<<~SQL)
        SELECT pg_get_constraintdef(c.oid)
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        WHERE c.contype = 'c' AND t.relname = #{connection.quote(table)}
      SQL
    end
    pattern = /\(\(?#{Regexp.escape(column)} = ANY \(ARRAY\[(.+?)\]\)\)/
    definition = definitions.find { |d| d.match?(pattern) }
    return nil unless definition

    definition[pattern, 1].scan(/'([^']*)'::text/).flatten.sort
  end

  MODELS.each do |model|
    model.defined_enums.each do |attribute, mapping|
      test "#{model.name}.#{attribute} matches its database constraint" do
        allowed = check_values(model.table_name, attribute)
        assert allowed, "no CHECK constraint found for #{model.table_name}.#{attribute}"
        assert_equal allowed, mapping.values.sort
      end
    end
  end
end
