# frozen_string_literal: true

# Asks the addon about a submitted attempt under a poll claim.
class ReconcileAttemptJob < ApplicationJob
  queue_as :publish

  def perform(attempt_id, fencing_token)
    attempt = PublishAttempt.find_by(id: attempt_id)
    Publishing::Reconciler.new(attempt, fencing_token).run if attempt
  end
end
