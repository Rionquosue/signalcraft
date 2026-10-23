# frozen_string_literal: true

# Recurring dispatcher pass (config/recurring.yml). Overlapping runs are
# harmless, so no concurrency control is needed.
class DispatchJob < ApplicationJob
  queue_as :dispatch

  def perform
    Publishing::Dispatcher.new.run
  end
end
