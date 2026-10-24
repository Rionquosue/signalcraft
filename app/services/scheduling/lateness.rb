# frozen_string_literal: true

module Scheduling
  # The missed-schedule rule (design specifications/02, Lateness and missed
  # schedules). A scheduled target that has not been claimed within the grace
  # window after its due time:
  #
  # - in queue mode, moves to its queue's next future slot occurrence;
  # - in manual or now mode, becomes needs_attention (schedule_missed) and
  #   waits for an explicit Publish now or Reschedule.
  #
  # Paused accounts are skipped: their targets are not claimed while paused,
  # and resuming applies this rule (ChannelQueue#resume!). The same rule runs
  # after a worker outage, so overdue posts are never flooded out.
  class Lateness
    Result = Struct.new(:moved, :missed, keyword_init: true)

    def self.apply!(now: Time.current, grace: SignalCraft.settings.missed_schedule_grace_seconds, accounts: nil)
      new(now: now, grace: grace).apply!(accounts: accounts)
    end

    def initialize(now:, grace:)
      @now = now
      @cutoff = now - grace.seconds
    end

    # Targets the rule would act on, for the Resume preview.
    def overdue(accounts: nil)
      scope = PostTarget.where(state: "scheduled", claim_owner: nil).where("due_at < ?", @cutoff)
                        .where.not(social_account_id: ChannelQueue.where(paused: true).select(:social_account_id))
      accounts ? scope.where(social_account_id: accounts) : scope
    end

    def apply!(accounts: nil)
      result = Result.new(moved: [], missed: [])
      scope = overdue(accounts: accounts)
      scope.where.not(mode: "queue").pluck(:id).each do |id|
        result.missed << id if mark_missed(id)
      end
      scope.where(mode: "queue").distinct.pluck(:social_account_id).each do |account_id|
        result.moved.concat(reassign(account_id))
      end
      result
    end

    private

    def mark_missed(id)
      PostTarget.transaction do
        target = PostTarget.lock("FOR UPDATE SKIP LOCKED").find_by(id: id)
        next false unless target&.scheduled? && target.claim_owner.nil? && target.due_at && target.due_at < @cutoff

        target.update!(state: "needs_attention", attention_reason: "schedule_missed")
        OutboxEvent.announce!("post_target.schedule_missed", subject: target, workspace: target.workspace)
        AuditEvent.record!(action: "post_target.schedule_missed", actor: nil, workspace: target.workspace,
                           subject: target, details: { due_at: target.due_at.iso8601 })
        true
      end
    end

    # Locks the queue (queue before target, as everywhere), releases the
    # missed entries and reallocates. Each missed entry keeps its rank, so it
    # takes the next occurrence and later entries follow it.
    def reassign(account_id)
      queue = ChannelQueue.find_by(social_account_id: account_id)
      return [] unless queue

      ChannelQueue.transaction do
        queue.lock!
        next [] if queue.paused?

        missed = queue.queue_entries.joins(:post_target)
                      .where(post_targets: { state: "scheduled", claim_owner: nil })
                      .where("queue_entries.slot_occurrence_at < ?", @cutoff).pluck(:id)
        next [] if missed.empty?

        changes = QueueAllocator.new(queue, now: @now).apply!(release: missed, event: "queue.missed_schedules_moved")
        missed_ids = missed.to_set
        moved = changes.select { |change| missed_ids.include?(change.entry.id) }
        moved.each do |change|
          AuditEvent.record!(action: "post_target.moved_to_next_slot", actor: nil, workspace: queue.workspace,
                             subject: change.target,
                             details: { from: change.from&.iso8601, to: change.to&.iso8601 })
        end
        moved.map { |change| change.entry.post_target_id }
      end
    end
  end
end
