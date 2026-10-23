# frozen_string_literal: true

# Sends one claimed attempt. A duplicate or late job finds the claim already
# used or superseded and exits without publishing.
class PublishAttemptJob < ApplicationJob
  queue_as :publish

  def perform(attempt_id)
    attempt = PublishAttempt.find_by(id: attempt_id)
    Publishing::Executor.new(attempt).run if attempt
  end
end
