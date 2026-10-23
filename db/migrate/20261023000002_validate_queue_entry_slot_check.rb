# frozen_string_literal: true

# Second step of RelaxQueueEntrySlotCheck (design specifications/08, Migration rules).
class ValidateQueueEntrySlotCheck < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE queue_entries VALIDATE CONSTRAINT queue_entries_slot_needs_occurrence"
  end

  def down
  end
end
