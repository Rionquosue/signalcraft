# frozen_string_literal: true

# Schema 1.2 (design specifications/08, Changes in 1.2): a queue entry's slot
# reference only requires an occurrence. The old check (both null together)
# rejected deleting a slot that an entry still referenced, because
# ON DELETE SET NULL left the occurrence without its slot.
#
# Databases created from 0001_core_schema.sql at schema 1.2 already have the
# new constraint, so both steps are conditional. The constraint is added NOT
# VALID and validated by the next migration (08, Migration rules).
class RelaxQueueEntrySlotCheck < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint
                       WHERE conname = 'queue_entries_slot_needs_occurrence'
                         AND conrelid = 'queue_entries'::regclass) THEN
          ALTER TABLE queue_entries ADD CONSTRAINT queue_entries_slot_needs_occurrence
            CHECK (queue_slot_id IS NULL OR slot_occurrence_at IS NOT NULL) NOT VALID;
        END IF;
      END $$;
      ALTER TABLE queue_entries DROP CONSTRAINT IF EXISTS queue_entries_check;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE queue_entries DROP CONSTRAINT IF EXISTS queue_entries_slot_needs_occurrence;
      ALTER TABLE queue_entries ADD CONSTRAINT queue_entries_check
        CHECK ((queue_slot_id IS NULL) = (slot_occurrence_at IS NULL)) NOT VALID;
    SQL
  end
end
